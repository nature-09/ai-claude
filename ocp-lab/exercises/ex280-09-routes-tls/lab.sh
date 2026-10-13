# shellcheck shell=bash
EX_TITLE="TLS 라우트: edge, passthrough, re-encrypt 와 서비스 CA"
EX_SCOPE=namespace
NS="$U-tls"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  apply_manifest apps.yaml
  workdir
  make_ca "$WORK"
  oc project "$NS" >/dev/null
  local d; d="$(apps_domain)"
  info "실습용 CA: $WORK/ca.crt, $WORK/ca.key"
  info "사용할 호스트 이름:"
  echo "   edge        : $U-edge.$d"
  echo "   passthrough : $U-pass.$d"
  echo "   reencrypt   : $U-reencrypt.$d"
}

ex_grade() {
  local d; d="$(apps_domain)"; workdir
  section "edge"
  check "route web-edge: edge, 호스트 $U-edge.$d" route_is web-edge edge "$U-edge.$d"
  check "web-edge 가 실습 CA 로 서명된 인증서 사용 (curl --cacert 성공)" https_verified_has "https://$U-edge.$d/" 'edge route' "$WORK/ca.crt"
  check "web-edge: HTTP 요청은 HTTPS 로 리다이렉트" jp_eq "$NS" route/web-edge '{.spec.tls.insecureEdgeTerminationPolicy}' Redirect
  check "http://$U-edge.$d 접속 시 302 응답" redirect_302 "http://$U-edge.$d/"
  section "passthrough"
  check "Secret pass-cert (kubernetes.io/tls)" jp_eq "$NS" secret/pass-cert '{.type}' kubernetes.io/tls
  check "secure 에 pass-cert 가 /etc/tls 로 마운트" jp_has "$NS" deployment/secure '{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' '/etc/tls'
  check "route secure-pass: passthrough, 호스트 $U-pass.$d" route_is secure-pass passthrough "$U-pass.$d"
  check "passthrough 로 앱의 인증서가 그대로 보임 (curl --cacert 성공)" https_verified_has "https://$U-pass.$d/" 'passthrough route' "$WORK/ca.crt"
  section "reencrypt"
  check "Service internal 에 serving-cert 어노테이션 (internal-tls)" jp_eq "$NS" svc/internal '{.metadata.annotations.service\.beta\.openshift\.io/serving-cert-secret-name}' internal-tls
  check "서비스 CA 가 Secret internal-tls 발급" jp_eq "$NS" secret/internal-tls '{.type}' kubernetes.io/tls
  check "internal 에 internal-tls 가 /etc/tls 로 마운트" jp_has "$NS" deployment/internal '{.spec.template.spec.volumes[*].secret.secretName}' internal-tls
  check "route internal: reencrypt, 호스트 $U-reencrypt.$d" route_is internal reencrypt "$U-reencrypt.$d"
  check "reencrypt 라우트로 접속 성공" http_has "https://$U-reencrypt.$d/" 'reencrypt route'
}
redirect_302() { [ "$(http_code "$1")" = 302 ]; }
route_is() { jp_eq "$NS" "route/$1" '{.spec.tls.termination}' "$2" && jp_eq "$NS" "route/$1" '{.spec.host}' "$3"; }

ex_solve() {
  local d; d="$(apps_domain)"; workdir
  make_cert "$WORK" edge "$U-edge.$d"
  make_cert "$WORK" pass "$U-pass.$d"
  oc delete route web-edge secure-pass internal -n "$NS" --ignore-not-found >/dev/null
  oc create route edge web-edge -n "$NS" --service=web --hostname="$U-edge.$d" \
    --cert="$WORK/edge.crt" --key="$WORK/edge.key" --ca-cert="$WORK/ca.crt" --insecure-policy=Redirect >/dev/null
  oc create secret tls pass-cert -n "$NS" --cert="$WORK/pass.crt" --key="$WORK/pass.key" --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc set volumes deployment/secure -n "$NS" --add --name=tls --type=secret --secret-name=pass-cert --mount-path=/etc/tls --overwrite >/dev/null
  oc create route passthrough secure-pass -n "$NS" --service=secure --port=8443 --hostname="$U-pass.$d" >/dev/null
  oc annotate service internal -n "$NS" service.beta.openshift.io/serving-cert-secret-name=internal-tls --overwrite >/dev/null
  wait_until 60 res_exists "$NS" secret/internal-tls
  oc set volumes deployment/internal -n "$NS" --add --name=tls --type=secret --secret-name=internal-tls --mount-path=/etc/tls --overwrite >/dev/null
  oc create route reencrypt internal -n "$NS" --service=internal --port=8443 --hostname="$U-reencrypt.$d" >/dev/null
  wait_deploy secure "$NS"; wait_deploy internal "$NS"; sleep 5
}
