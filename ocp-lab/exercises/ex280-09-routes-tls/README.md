# ex280-09-routes-tls — TLS 라우트 (edge, passthrough, re-encrypt)

## 목표 (EX280: Configure network security — TLS)
- 사내 CA 로 서명한 인증서로 **edge** 라우트를 만든다
- 애플리케이션이 직접 TLS 를 처리하는 **passthrough** 라우트를 만든다
- OpenShift **서비스 CA** 가 발급한 인증서로 **re-encrypt** 라우트를 만든다

| 종류 | TLS 종료 위치 | 라우터 → 파드 구간 | 인증서 |
|---|---|---|---|
| edge | 라우터 | 평문 HTTP | 라우트에 지정 (없으면 기본 와일드카드) |
| passthrough | 파드(앱) | 암호화 그대로 전달 | 앱이 가진 인증서 |
| reencrypt | 라우터에서 풀고 다시 암호화 | HTTPS | 외부용: 라우트 / 내부용: 서비스 CA 등 |

## 시작
```bash
lab start ex280-09
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-09-routes-tls       # ca.crt, ca.key (실습용 사내 CA)
```
`web`(HTTP 8080), `secure`(HTTPS 8443, 인증서 없음), `internal`(HTTPS 8443, 인증서 없음) 앱이 준비되어 있습니다.
`secure`, `internal` 은 `/etc/tls/tls.crt`, `/etc/tls/tls.key` 가 있어야 8443 포트를 엽니다.

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | edge 인증서 | `${LAB_USER}-edge.${APPS_DOMAIN}` 용 인증서를 실습 CA 로 서명 |
| 2 | edge 라우트 | 이름 `web-edge`, 서비스 `web`, HTTP → HTTPS 리다이렉트 |
| 3 | passthrough 인증서 | `${LAB_USER}-pass.${APPS_DOMAIN}` 용 인증서 → TLS Secret `pass-cert` |
| 4 | 마운트 | `pass-cert` 를 `secure` 의 `/etc/tls` 에 마운트 |
| 5 | passthrough 라우트 | 이름 `secure-pass`, 서비스 `secure` 8443, 호스트 `${LAB_USER}-pass.${APPS_DOMAIN}` |
| 6 | 서비스 CA | Service `internal` 에 인증서 Secret `internal-tls` 를 자동 발급받도록 어노테이션 |
| 7 | 마운트 | `internal-tls` 를 `internal` 의 `/etc/tls` 에 마운트 |
| 8 | reencrypt 라우트 | 이름 `internal`, 서비스 `internal` 8443, 호스트 `${LAB_USER}-reencrypt.${APPS_DOMAIN}` |

## 풀이 가이드

### 인증서 만들기 (openssl)
```bash
cert() {   # cert <이름> <호스트>
  openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$2" -keyout $1.key -out $1.csr
  openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -sha256 \
    -extfile <(printf "subjectAltName=DNS:$2") -out $1.crt
}
cert edge ${LAB_USER}-edge.${APPS_DOMAIN}
cert pass ${LAB_USER}-pass.${APPS_DOMAIN}
openssl x509 -in edge.crt -noout -subject -issuer -ext subjectAltName
```
> 최신 브라우저·curl 은 CN 이 아닌 **SAN(subjectAltName)** 을 봅니다. SAN 을 꼭 넣으세요.

### edge
```bash
oc create route edge web-edge --service=web --hostname=${LAB_USER}-edge.${APPS_DOMAIN} \
   --cert=edge.crt --key=edge.key --ca-cert=ca.crt --insecure-policy=Redirect
curl --cacert ca.crt https://${LAB_USER}-edge.${APPS_DOMAIN}/
curl -I http://${LAB_USER}-edge.${APPS_DOMAIN}/          # 302 → https
```

### passthrough
```bash
oc create secret tls pass-cert --cert=pass.crt --key=pass.key
oc set volumes deployment/secure --add --name=tls --type=secret --secret-name=pass-cert --mount-path=/etc/tls
oc logs deploy/secure | grep HTTPS                      # "HTTPS listening on :8443"
oc create route passthrough secure-pass --service=secure --port=8443 --hostname=${LAB_USER}-pass.${APPS_DOMAIN}
curl --cacert ca.crt https://${LAB_USER}-pass.${APPS_DOMAIN}/
openssl s_client -connect ${LAB_USER}-pass.${APPS_DOMAIN}:443 -servername ${LAB_USER}-pass.${APPS_DOMAIN} </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
```

### reencrypt + 서비스 CA
```bash
oc annotate service internal service.beta.openshift.io/serving-cert-secret-name=internal-tls
oc get secret internal-tls                               # 서비스 CA 가 자동 생성 (internal.<ns>.svc 용)
oc set volumes deployment/internal --add --name=tls --type=secret --secret-name=internal-tls --mount-path=/etc/tls
oc create route reencrypt internal --service=internal --port=8443 --hostname=${LAB_USER}-reencrypt.${APPS_DOMAIN}
curl -k https://${LAB_USER}-reencrypt.${APPS_DOMAIN}/
```
`--dest-ca-cert` 를 생략하면 라우터가 서비스 CA 를 신뢰합니다. 외부 클라이언트용 인증서도 바꾸려면 `--cert/--key` 를 함께 지정합니다.

### 더 알아보기
- 서비스 CA 번들을 ConfigMap 으로 주입: `oc annotate configmap <cm> service.beta.openshift.io/inject-cabundle=true`
- 웹 콘솔 **Networking → Routes → Create Route** 에서 Secure route, TLS termination 을 고를 수 있습니다.
- 라우트 YAML: `oc get route web-edge -o yaml` 의 `spec.tls` 확인

## 채점 / 정리
```bash
lab grade ex280-09
lab finish ex280-09
```
