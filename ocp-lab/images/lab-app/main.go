// lab-app: OCP 실습용 샘플 애플리케이션
//
// 한 개의 바이너리로 여러 실습 시나리오를 처리합니다.
//   - HTTP  :PORT (기본 8080)        배포, 서비스, 라우트, 프로브, HPA
//   - HTTPS :TLS_PORT (기본 8443)    /etc/tls/tls.crt, tls.key 가 있을 때만 (passthrough/reencrypt)
//   - TCP   :TCP_PORT (기본 9000)    한 줄씩 되돌려 주는 echo 서버 (NodePort/LoadBalancer)
//
// 빌드할 때 버전(-X main.version)과 고장 모드(-X main.broken=true)를 넣습니다.
package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

var (
	version = "dev"
	broken  = "false"
)

var (
	startedAt   = time.Now()
	notReady    atomic.Bool
	unhealthy   atomic.Bool
	readyDelay  time.Duration
	hostname, _ = os.Hostname()
)

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

func main() {
	if len(os.Args) > 1 {
		os.Exit(client(os.Args[1:]))
	}

	log.SetFlags(log.LstdFlags)
	log.Printf("lab-app %s starting (pod=%s uid=%d gid=%d)", version, hostname, os.Getuid(), os.Getgid())

	if broken == "true" {
		log.Printf("FATAL: %s 버전은 설정 오류로 기동할 수 없습니다 (failed to load /etc/app/required.conf)", version)
		time.Sleep(2 * time.Second)
		os.Exit(1)
	}

	// 레거시 앱 흉내: root 가 아니면 기동 거부 (SCC 실습용 legacy 이미지에서 REQUIRE_ROOT=true)
	if env("REQUIRE_ROOT", "false") == "true" && os.Getuid() != 0 {
		log.Printf("FATAL: 이 레거시 애플리케이션은 root(UID 0)로 실행해야 합니다. 현재 UID=%d", os.Getuid())
		time.Sleep(2 * time.Second)
		os.Exit(1)
	}

	var missing []string
	for _, k := range strings.Split(env("REQUIRED_ENV", ""), ",") {
		if k = strings.TrimSpace(k); k != "" && os.Getenv(k) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		log.Printf("FATAL: 필수 환경 변수가 없습니다: %s", strings.Join(missing, ", "))
		time.Sleep(2 * time.Second)
		os.Exit(1)
	}

	if s, err := strconv.Atoi(env("READY_DELAY", "0")); err == nil {
		readyDelay = time.Duration(s) * time.Second
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/healthz", handleHealth)
	mux.HandleFunc("/readyz", handleReady)
	mux.HandleFunc("/fail-health", func(w http.ResponseWriter, r *http.Request) {
		unhealthy.Store(true)
		log.Printf("liveness 실패 모드로 전환 (/healthz -> 500)")
		fmt.Fprintln(w, "liveness probe will now fail")
	})
	mux.HandleFunc("/toggle-ready", func(w http.ResponseWriter, r *http.Request) {
		v := !notReady.Load()
		notReady.Store(v)
		log.Printf("readiness 강제 실패=%v", v)
		fmt.Fprintf(w, "notReady=%v\n", v)
	})
	mux.HandleFunc("/env", handleEnv)
	mux.HandleFunc("/config", handleConfig)
	mux.HandleFunc("/data", handleData)
	mux.HandleFunc("/cpu", handleCPU)
	mux.HandleFunc("/info", handleInfo)

	handler := logRequests(mux)

	port := env("PORT", "8080")
	go func() {
		log.Printf("HTTP listening on :%s", port)
		log.Fatal(http.ListenAndServe(":"+port, handler))
	}()

	certFile := env("TLS_CERT_FILE", "/etc/tls/tls.crt")
	keyFile := env("TLS_KEY_FILE", "/etc/tls/tls.key")
	if fileExists(certFile) && fileExists(keyFile) {
		tlsPort := env("TLS_PORT", "8443")
		go func() {
			log.Printf("HTTPS listening on :%s (cert=%s)", tlsPort, certFile)
			srv := &http.Server{Addr: ":" + tlsPort, Handler: handler, TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12}}
			log.Fatal(srv.ListenAndServeTLS(certFile, keyFile))
		}()
	}

	if tcpPort := env("TCP_PORT", "9000"); tcpPort != "0" {
		go tcpEcho(tcpPort)
	}

	select {}
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" && r.URL.Path != "/readyz" {
			log.Printf("%s %s %s from=%s", r.Method, r.URL.RequestURI(), r.Proto, r.RemoteAddr)
		}
		next.ServeHTTP(w, r)
	})
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	msg := env("APP_MESSAGE", "Welcome to the OpenShift lab")
	fmt.Fprintf(w, "Hello from lab-app (version=%s, pod=%s) %s\n", version, hostname, msg)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if unhealthy.Load() {
		http.Error(w, "unhealthy", http.StatusInternalServerError)
		return
	}
	fmt.Fprintln(w, "ok")
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	if time.Since(startedAt) < readyDelay {
		http.Error(w, fmt.Sprintf("warming up (%s left)", (readyDelay-time.Since(startedAt)).Round(time.Second)), http.StatusServiceUnavailable)
		return
	}
	if notReady.Load() || fileExists("/tmp/notready") {
		http.Error(w, "not ready", http.StatusServiceUnavailable)
		return
	}
	fmt.Fprintln(w, "ready")
}

func handleEnv(w http.ResponseWriter, r *http.Request) {
	vars := os.Environ()
	sort.Strings(vars)
	for _, v := range vars {
		fmt.Fprintln(w, v)
	}
}

func handleConfig(w http.ResponseWriter, r *http.Request) {
	dir := env("CONFIG_DIR", "/etc/app-config")
	entries, err := os.ReadDir(dir)
	if err != nil {
		http.Error(w, fmt.Sprintf("%s: %v", dir, err), http.StatusNotFound)
		return
	}
	for _, e := range entries {
		// ConfigMap/Secret 볼륨의 ..data 같은 숨김 링크는 건너뜀
		if strings.HasPrefix(e.Name(), "..") {
			continue
		}
		p := filepath.Join(dir, e.Name())
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		fmt.Fprintf(w, "==> %s <==\n%s\n", p, strings.TrimRight(string(b), "\n"))
	}
}

func handleData(w http.ResponseWriter, r *http.Request) {
	dir := env("DATA_DIR", "/data")
	switch r.Method {
	case http.MethodGet:
		if name := r.URL.Query().Get("file"); name != "" {
			b, err := os.ReadFile(filepath.Join(dir, filepath.Base(name)))
			if err != nil {
				http.Error(w, err.Error(), http.StatusNotFound)
				return
			}
			w.Write(b)
			return
		}
		entries, err := os.ReadDir(dir)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		for _, e := range entries {
			if info, err := e.Info(); err == nil && !e.IsDir() {
				fmt.Fprintf(w, "%s\t%d bytes\t%s\n", e.Name(), info.Size(), info.ModTime().Format(time.RFC3339))
			}
		}
	case http.MethodPost, http.MethodPut:
		name := filepath.Base(r.URL.Query().Get("file"))
		if name == "" || name == "." || name == "/" {
			http.Error(w, "file 파라미터가 필요합니다 (예: /data?file=hello.txt)", http.StatusBadRequest)
			return
		}
		body, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		if err := os.WriteFile(filepath.Join(dir, name), body, 0o664); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		fmt.Fprintf(w, "saved %s (%d bytes) on pod %s\n", filepath.Join(dir, name), len(body), hostname)
	default:
		http.Error(w, "GET 또는 POST만 지원합니다", http.StatusMethodNotAllowed)
	}
}

// /cpu?ms=500 : 지정한 시간 동안 CPU를 사용 (HPA 실습용)
func handleCPU(w http.ResponseWriter, r *http.Request) {
	ms, err := strconv.Atoi(r.URL.Query().Get("ms"))
	if err != nil || ms <= 0 {
		ms = 200
	}
	if ms > 10000 {
		ms = 10000
	}
	deadline := time.Now().Add(time.Duration(ms) * time.Millisecond)
	x := 0
	for time.Now().Before(deadline) {
		for i := 0; i < 1000; i++ {
			x += i * i
		}
	}
	fmt.Fprintf(w, "burned %dms of cpu on %s (%d)\n", ms, hostname, x%7)
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	var ips []string
	if addrs, err := net.InterfaceAddrs(); err == nil {
		for _, a := range addrs {
			if ipn, ok := a.(*net.IPNet); ok && !ipn.IP.IsLoopback() {
				ips = append(ips, ipn.IP.String())
			}
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"version":  version,
		"hostname": hostname,
		"ips":      ips,
		"uid":      os.Getuid(),
		"gid":      os.Getgid(),
		"uptime":   time.Since(startedAt).Round(time.Second).String(),
		"tls":      r.TLS != nil,
	})
}

func tcpEcho(port string) {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Printf("TCP echo 비활성화: %v", err)
		return
	}
	log.Printf("TCP echo listening on :%s", port)
	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			log.Printf("TCP connection from %s", c.RemoteAddr())
			fmt.Fprintf(c, "lab-app tcp echo (version=%s, pod=%s)\n", version, hostname)
			c.SetDeadline(time.Now().Add(60 * time.Second))
			sc := bufio.NewScanner(c)
			for sc.Scan() {
				fmt.Fprintf(c, "echo: %s\n", sc.Text())
			}
		}(c)
	}
}

// 컨테이너 안에서 쓰는 간단한 클라이언트 (curl 대용)
//
//	lab-app get <url>            HTTP GET, 2xx가 아니면 종료 코드 1
//	lab-app tcp <host:port>      TCP echo 서버에 접속해 첫 줄 출력
//	lab-app version
func client(args []string) int {
	switch args[0] {
	case "version":
		fmt.Println(version)
		return 0
	case "get":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: lab-app get <url>")
			return 2
		}
		c := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
		resp, err := c.Get(args[1])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		defer resp.Body.Close()
		io.Copy(os.Stdout, resp.Body)
		if resp.StatusCode/100 != 2 {
			fmt.Fprintf(os.Stderr, "HTTP %d\n", resp.StatusCode)
			return 1
		}
		return 0
	case "tcp":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: lab-app tcp <host:port>")
			return 2
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		c, err := (&net.Dialer{}).DialContext(ctx, "tcp", args[1])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(3 * time.Second))
		line, err := bufio.NewReader(c).ReadString('\n')
		fmt.Print(line)
		if err != nil {
			return 1
		}
		return 0
	}
	fmt.Fprintf(os.Stderr, "unknown command %q\n", args[0])
	return 2
}
