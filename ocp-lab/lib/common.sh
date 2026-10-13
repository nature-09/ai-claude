# shellcheck shell=bash
# ocp-lab 공통 함수 (bin/lab, bin/lab-admin, exercises/*/lab.sh 에서 사용)

LAB_VERSION="$(cat "$LAB_HOME/VERSION" 2>/dev/null || echo dev)"

# ---------------------------------------------------------------- 출력
if [ -t 1 ]; then
  C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YEL=$'\e[33m' C_BLU=$'\e[36m' C_BLD=$'\e[1m' C_OFF=$'\e[0m'
else
  C_RED='' C_GRN='' C_YEL='' C_BLU='' C_BLD='' C_OFF=''
fi
info()  { [ -n "${LAB_QUIET:-}" ] || echo "${C_BLU}>>${C_OFF} $*"; }
warn()  { echo "${C_YEL}!!${C_OFF} $*" >&2; }
die()   { echo "${C_RED}ERROR:${C_OFF} $*" >&2; exit 1; }
title() { [ -n "${LAB_QUIET:-}" ] || echo; [ -n "${LAB_QUIET:-}" ] || echo "${C_BLD}== $* ==${C_OFF}"; }

# ---------------------------------------------------------------- 설정
# KEY=VALUE 형식 파일을 읽되, 이미 환경 변수로 지정된 값은 덮어쓰지 않음
lab_load_env() {
  local f="$1" line key val
  [ -r "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[2]}" val="${BASH_REMATCH[3]}"
    val="${val%%[[:space:]]#*}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$val" in \"*\") val="${val:1:${#val}-2}" ;; \'*\') val="${val:1:${#val}-2}" ;; esac
    if [ -z "${!key+x}" ]; then export "$key=$val"; fi
  done < "$f"
}

lab_load_env "$HOME/.ocp-lab/lab.env"
lab_load_env "${LAB_CONFIG:-/etc/ocp-lab/lab.env}"

: "${LAB_REPO_PREFIX:=ocp-lab}"
: "${LAB_SHARED:=true}"
: "${LAB_WORKDIR:=$HOME/ocp-lab-work}"
: "${LAB_OPERATOR_PACKAGE:=rhbk-operator}"
: "${LAB_INSECURE_TLS:=true}"
: "${LAB_DEFAULT_PASSWORD:=redhat123}"
export LAB_REPO_PREFIX LAB_SHARED LAB_WORKDIR LAB_OPERATOR_PACKAGE

lab_images() {
  local base="${LAB_REGISTRY:-REGISTRY-NOT-SET}/$LAB_REPO_PREFIX"
  IMG_APP="$base/lab-app"
  IMG_TOOLBOX="$base/lab-toolbox:$LAB_VERSION"
  IMG_UBI="$base/ubi9-ubi:latest"
  IMG_HTTPD="$base/ubi9-httpd-24:latest"
  IMG_MYSQL="$base/rhel9-mysql-80:latest"
  export IMG_APP IMG_TOOLBOX IMG_UBI IMG_HTTPD IMG_MYSQL
}
lab_images

is_shared() { [ "$LAB_SHARED" = "true" ]; }

# 수강생 이름(네임스페이스·사용자 접두어) 결정: LAB_USER → ~/.ocp-lab/user → (1인 모드) lab
lab_resolve_user() {
  if [ -z "${LAB_USER:-}" ] && [ -r "$HOME/.ocp-lab/user" ]; then
    LAB_USER="$(tr -d '[:space:]' < "$HOME/.ocp-lab/user")"
  fi
  if [ -z "${LAB_USER:-}" ]; then
    is_shared && die "수강생 이름이 없습니다. 먼저 'lab init <이름>' 을 실행하세요 (예: lab init student01)"
    LAB_USER=lab
  fi
  valid_user "$LAB_USER" || die "수강생 이름 '$LAB_USER' 형식 오류: 소문자/숫자/하이픈, 2~20자"
  U="$LAB_USER"
  export LAB_USER U
}
valid_user() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])$ ]]; }

require_oc() {
  command -v oc >/dev/null 2>&1 || die "oc 명령이 없습니다"
  oc whoami >/dev/null 2>&1 || die "OCP에 로그인되어 있지 않습니다. 'lab login' 또는 'oc login <API URL>' 을 먼저 하세요"
}
require_registry() {
  [ -n "${LAB_REGISTRY:-}" ] || die "LAB_REGISTRY 가 설정되지 않았습니다 (/etc/ocp-lab/lab.env 확인)"
}
require_cmd() {
  local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "'$c' 명령이 필요합니다"; done
}

apps_domain() {
  [ -n "${APPS_DOMAIN:-}" ] || APPS_DOMAIN="$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)"
  echo "$APPS_DOMAIN"
}
api_url() { oc whoami --show-server; }

# ---------------------------------------------------------------- 네임스페이스
# 실습 네임스페이스 생성 (이미 있으면 지우고 다시 만듦). 현재 프로젝트는 바꾸지 않음
ns_new() {
  local ns="$1"
  if oc get namespace "$ns" >/dev/null 2>&1; then
    info "기존 네임스페이스 $ns 삭제 후 다시 만듭니다"
    oc delete project "$ns" --wait=true --timeout=180s >/dev/null 2>&1 || true
    local _i; for _i in $(seq 1 90); do oc get namespace "$ns" >/dev/null 2>&1 || break; sleep 2; done
  fi
  oc adm new-project "$ns" >/dev/null || die "네임스페이스 $ns 생성 실패"
  oc label namespace "$ns" "ocp-lab/student=$U" "ocp-lab/exercise=${EX_ID:-none}" --overwrite >/dev/null
  info "네임스페이스 준비: $ns"
}
ns_del() {
  local ns
  for ns in "$@"; do
    oc get namespace "$ns" >/dev/null 2>&1 || continue
    info "네임스페이스 삭제: $ns"
    oc delete project "$ns" --wait=false >/dev/null 2>&1 || true
  done
}
ns_exists() { oc get namespace "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 템플릿/파일
# @@KEY@@ 토큰 치환. 추가 치환은 KEY=VALUE 인자로 전달
render() {
  local file="$1"; shift
  local -a expr=(
    -e "s|@@LAB_USER@@|$U|g"
    -e "s|@@LAB_REGISTRY@@|${LAB_REGISTRY:-}|g"
    -e "s|@@IMG_APP@@|$IMG_APP|g"
    -e "s|@@IMG_TOOLBOX@@|$IMG_TOOLBOX|g"
    -e "s|@@IMG_UBI@@|$IMG_UBI|g"
    -e "s|@@IMG_HTTPD@@|$IMG_HTTPD|g"
    -e "s|@@IMG_MYSQL@@|$IMG_MYSQL|g"
    -e "s|@@APPS_DOMAIN@@|$(apps_domain)|g"
  )
  local kv; for kv in "$@"; do expr+=(-e "s|@@${kv%%=*}@@|${kv#*=}|g"); done
  sed "${expr[@]}" "$file"
}
# 실습 매니페스트(exercises/<id>/manifests/*.yaml) 적용
apply_manifest() {
  local name="$1"; shift
  render "$EX_DIR/manifests/$name" "$@" | oc apply -f - >/dev/null || die "$name 적용 실패"
}
# 학생용 파일(exercises/<id>/files)을 작업 디렉터리로 복사 (토큰 치환)
copy_files() {
  WORK="$LAB_WORKDIR/$EX_ID"
  rm -rf "$WORK" && mkdir -p "$WORK"
  if [ -d "$EX_DIR/files" ]; then
    cp -r "$EX_DIR/files/." "$WORK/"
    local f
    while IFS= read -r -d '' f; do
      render "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
    done < <(find "$WORK" -type f -print0)
  fi
  info "작업 디렉터리: $WORK"
}
workdir() { WORK="$LAB_WORKDIR/$EX_ID"; mkdir -p "$WORK"; }

# ---------------------------------------------------------------- 대기
wait_deploy() { # name ns [timeout]
  oc rollout status "deployment/$1" -n "$2" --timeout="${3:-180s}" >/dev/null 2>&1
}
wait_until() { # timeout_sec cmd...
  local t="$1"; shift
  local end=$((SECONDS + t))
  until "$@" >/dev/null 2>&1; do [ $SECONDS -ge $end ] && return 1; sleep 3; done
}

# ---------------------------------------------------------------- 조회
jp() { # ns resource jsonpath
  local ns="$1" res="$2" path="$3"
  if [ -n "$ns" ]; then oc get "$res" -n "$ns" -o "jsonpath=$path" 2>/dev/null
  else oc get "$res" -o "jsonpath=$path" 2>/dev/null; fi
}
jp_eq()  { [ "$(jp "$1" "$2" "$3")" = "$4" ]; }
jp_has() { jp "$1" "$2" "$3" | grep -qE -- "$4"; }
res_exists() { # ns resource
  if [ -n "$1" ]; then oc get "$2" -n "$1" >/dev/null 2>&1; else oc get "$2" >/dev/null 2>&1; fi
}
res_absent() { ! res_exists "$@"; }
deploy_ready() { # name ns [min]
  local r; r="$(jp "$2" "deployment/$1" '{.status.readyReplicas}')"
  [ "${r:-0}" -ge "${3:-1}" ]
}
deploy_json_has() { # name ns regex   (deployment 전체 JSON에서 패턴 검색)
  oc get "deployment/$1" -n "$2" -o json 2>/dev/null | grep -qE -- "$3"
}
route_host() { jp "$2" "route/$1" '{.spec.host}'; }

http_get() { # url [curl 옵션...]  → 본문 출력
  local url="$1"; shift
  curl -sS -m 8 -k "$@" "$url" 2>/dev/null
}
http_has() { # url regex [curl 옵션...]
  local url="$1" re="$2"; shift 2
  http_get "$url" "$@" | grep -qE -- "$re"
}
# 실습 CA 로 서버 인증서를 검증하면서 요청 (-k 없이).
# CA 파일이 없으면(강사가 다른 계정에서 채점) 발급자가 실습 CA(O=OCP Lab)인지로 대신 확인
https_verified_has() { # url regex cafile
  if [ -r "$3" ]; then
    curl -sS -m 8 --cacert "$3" "$1" 2>/dev/null | grep -qE -- "$2"
  else
    local h="${1#https://}"; h="${h%%/*}"
    http_has "$1" "$2" && openssl s_client -connect "$h:443" -servername "$h" </dev/null 2>/dev/null |
      openssl x509 -noout -issuer 2>/dev/null | grep -q 'OCP Lab'
  fi
}
http_code() { curl -s -m 8 -k -o /dev/null -w '%{http_code}' "$@" 2>/dev/null; }
route_has() { # route ns regex [path]
  local h; h="$(route_host "$1" "$2")"; [ -n "$h" ] || return 1
  local scheme=http
  [ -n "$(jp "$2" "route/$1" '{.spec.tls.termination}')" ] && scheme=https
  http_has "$scheme://$h${4:-/}" "$3" -L
}
# 파드 안에서 HTTP 요청 (네트워크 정책/내부 통신 확인)
pod_http_code() { # ns deploy url
  oc exec -n "$1" "deploy/$2" -- curl -s -m 4 -o /dev/null -w '%{http_code}' "$3" 2>/dev/null
}
pod_http_ok() { [ "$(pod_http_code "$@")" = "200" ]; }
# 연결 자체가 안 되면 curl 이 000 을 출력 (exec 실패로 빈 값이면 차단으로 보지 않음)
pod_http_blocked() { local c; c="$(pod_http_code "$@")"; [ "$c" = "000" ]; }
pod_exec_has() { # ns deploy regex cmd...
  local ns="$1" d="$2" re="$3"; shift 3
  oc exec -n "$ns" "deploy/$d" -- "$@" 2>/dev/null | grep -qE -- "$re"
}
can_i() { # yes|no verb resource ns as [group]
  local want="$1" verb="$2" res="$3" ns="$4" as="$5" grp="${6:-}" out
  local -a a=(auth can-i "$verb" "$res" "--as=$as")
  [ -n "$ns" ] && a+=(-n "$ns")
  [ -n "$grp" ] && a+=("--as-group=$grp" "--as-group=system:authenticated")
  out="$(oc "${a[@]}" 2>/dev/null)"
  [ "$out" = "$want" ]
}
# bash /dev/tcp 로 TCP echo 서버 확인
tcp_has() { # host port regex
  timeout 6 bash -c "exec 3<>/dev/tcp/$1/$2 && head -n1 <&3" 2>/dev/null | grep -qE -- "$3"
}

# ---------------------------------------------------------------- 인증서
make_ca() { # dir  → dir/ca.crt, dir/ca.key
  local d="$1"
  [ -f "$d/ca.crt" ] && return 0
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -subj "/O=OCP Lab/CN=OCP Lab CA ($U)" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "$d/ca.key" -out "$d/ca.crt" >/dev/null 2>&1 || die "CA 생성 실패"
}
make_cert() { # dir name host  → dir/name.crt, name.key (dir/ca.* 로 서명)
  local d="$1" n="$2" h="$3"
  openssl req -new -newkey rsa:2048 -nodes -subj "/O=OCP Lab/CN=$h" \
    -keyout "$d/$n.key" -out "$d/$n.csr" >/dev/null 2>&1 &&
  openssl x509 -req -sha256 -days 365 -in "$d/$n.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial \
    -extfile <(printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$h") \
    -out "$d/$n.crt" >/dev/null 2>&1 || die "$h 인증서 생성 실패"
}

# ---------------------------------------------------------------- OAuth (htpasswd IdP)
htpasswd_line() { # user password
  if command -v htpasswd >/dev/null 2>&1; then htpasswd -nbB "$1" "$2"
  else printf '%s:%s\n' "$1" "$(openssl passwd -apr1 "$2")"; fi
}
oauth_has_idp() { jp '' oauth/cluster '{.spec.identityProviders[*].name}' | tr ' ' '\n' | grep -qx -- "$1"; }
oauth_add_idp() { # name secret
  local name="$1" secret="$2" idp
  oauth_has_idp "$name" && return 0
  idp="{\"name\":\"$name\",\"mappingMethod\":\"claim\",\"type\":\"HTPasswd\",\"htpasswd\":{\"fileData\":{\"name\":\"$secret\"}}}"
  if [ -z "$(jp '' oauth/cluster '{.spec.identityProviders}')" ]; then
    oc patch oauth cluster --type=merge -p "{\"spec\":{\"identityProviders\":[$idp]}}" >/dev/null
  else
    oc patch oauth cluster --type=json -p "[{\"op\":\"add\",\"path\":\"/spec/identityProviders/-\",\"value\":$idp}]" >/dev/null
  fi
}
oauth_remove_idp() { # name  (동시 수정 충돌에 대비해 resourceVersion 포함 replace + 재시도)
  local name="$1"
  require_cmd jq
  for _ in 1 2 3 4 5; do
    oauth_has_idp "$name" || return 0
    oc get oauth cluster -o json |
      jq --arg n "$name" '.spec.identityProviders |= map(select(.name != $n))' |
      oc replace -f - >/dev/null 2>&1 && { info "OAuth IdP 제거: $name"; return 0; }
    sleep 2
  done
  warn "OAuth IdP $name 제거 실패 (oc edit oauth cluster 로 직접 지우세요)"
}
# 별도 kubeconfig로 로그인 시험 (현재 로그인 상태는 건드리지 않음)
login_ok() { # user password
  local kc; kc="$(mktemp)"
  oc login "$(api_url)" -u "$1" -p "$2" --insecure-skip-tls-verify=true --kubeconfig="$kc" >/dev/null 2>&1
  local rc=$?
  rm -f "$kc"; return $rc
}

# ---------------------------------------------------------------- 채점
GRADE_PASS=0 GRADE_FAIL=0 GRADE_SKIP=0 GRADE_SCORE=0 GRADE_MAX=0
# check [-p 점수] "설명" 명령 [인자...]
check() {
  local pts=0
  if [ "$1" = "-p" ]; then pts="$2"; shift 2; fi
  local desc="$1"; shift
  GRADE_MAX=$((GRADE_MAX + pts))
  if "$@" >/dev/null 2>&1; then
    GRADE_PASS=$((GRADE_PASS + 1)); GRADE_SCORE=$((GRADE_SCORE + pts))
    [ -n "${LAB_QUIET:-}" ] || printf ' %s[PASS]%s %s%s\n' "$C_GRN" "$C_OFF" "$desc" "$( [ "$pts" -gt 0 ] && echo " ($pts점)")"
  else
    GRADE_FAIL=$((GRADE_FAIL + 1))
    [ -n "${LAB_QUIET:-}" ] || printf ' %s[FAIL]%s %s%s\n' "$C_RED" "$C_OFF" "$desc" "$( [ "$pts" -gt 0 ] && echo " (0/$pts점)")"
  fi
}
skip() {
  GRADE_SKIP=$((GRADE_SKIP + 1))
  [ -n "${LAB_QUIET:-}" ] || printf ' %s[SKIP]%s %s\n' "$C_YEL" "$C_OFF" "$*"
}
section() { [ -n "${LAB_QUIET:-}" ] || printf '\n %s%s%s\n' "$C_BLD" "$*" "$C_OFF"; }
grade_summary() {
  local total=$((GRADE_PASS + GRADE_FAIL)) result
  if [ "$GRADE_MAX" -gt 0 ]; then
    result="SCORE $GRADE_SCORE/$GRADE_MAX"
    [ "$GRADE_SCORE" -ge $((GRADE_MAX * 70 / 100)) ] && result="$result PASS" || result="$result FAIL"
  else
    result="PASS $GRADE_PASS/$total"
    [ "$GRADE_SKIP" -gt 0 ] && result="$result (SKIP $GRADE_SKIP)"
  fi
  if [ -n "${LAB_QUIET:-}" ]; then
    echo "$result"
  else
    echo
    if [ "$GRADE_FAIL" -eq 0 ]; then echo "${C_GRN}${C_BLD}결과: $result — 모두 통과했습니다${C_OFF}"
    else echo "${C_YEL}${C_BLD}결과: $result — 실패 항목을 확인하세요 (lab guide $EX_ID)${C_OFF}"; fi
  fi
  mkdir -p "$HOME/.ocp-lab"
  echo "$(date '+%F %T') $U $EX_ID $result" >> "$HOME/.ocp-lab/results.log" 2>/dev/null || true
  [ "$GRADE_FAIL" -eq 0 ]
}

# ---------------------------------------------------------------- 공통 앱 배포
# lab-app 배포 + 서비스 (컨테이너 이름은 이미지 이름을 따라 'lab-app')
app_deploy() { # ns name tag [replicas]
  oc create deployment "$2" -n "$1" --image="$IMG_APP:$3" --port=8080 --replicas="${4:-1}" >/dev/null || die "$2 배포 실패"
  oc expose deployment "$2" -n "$1" --port=8080 --target-port=8080 >/dev/null || die "$2 서비스 생성 실패"
}
app_route() { oc expose service "$2" -n "$1" >/dev/null || die "$2 라우트 생성 실패"; }
