# shellcheck shell=bash
EX_TITLE="SCC 와 서비스 어카운트로 권한이 필요한 앱 실행"
EX_SCOPE=namespace
NS="$U-scc"
EX_NAMESPACES=("$NS")
SA_FULL="system:serviceaccount:$NS:legacy-sa"

ex_start() {
  ns_new "$NS"
  oc create deployment legacy -n "$NS" --image="$IMG_APP:legacy" --port=80 >/dev/null
  oc expose deployment legacy -n "$NS" --port=80 >/dev/null
  oc expose service legacy -n "$NS" >/dev/null
  oc project "$NS" >/dev/null
  info "레거시 앱 legacy 를 배포했습니다 (root 로 80 포트를 쓰는 앱). 'oc get pods' 로 상태를 보세요"
}

ex_grade() {
  check "ServiceAccount legacy-sa 존재" res_exists "$NS" sa/legacy-sa
  check "legacy-sa 가 anyuid SCC 사용 가능" can_i yes use securitycontextconstraints/anyuid "$NS" "$SA_FULL"
  check "legacy-sa 는 privileged SCC 불가 (최소 권한)" can_i no use securitycontextconstraints/privileged "$NS" "$SA_FULL"
  check "Deployment legacy 가 legacy-sa 사용" jp_eq "$NS" deployment/legacy '{.spec.template.spec.serviceAccountName}' legacy-sa
  check "legacy 파드가 anyuid SCC 로 실행" jp_has "$NS" pods '{.items[?(@.status.phase=="Running")].metadata.annotations.openshift\.io/scc}' 'anyuid'
  check "legacy 가 Ready" deploy_ready legacy "$NS"
  check "Route legacy 로 응답" route_has legacy "$NS" 'Hello from lab-app'
  check "앱이 UID 0 으로 동작" route_has legacy "$NS" '"uid":0' /info
}

ex_solve() {
  oc create serviceaccount legacy-sa -n "$NS" >/dev/null 2>&1 || true
  oc adm policy add-scc-to-user anyuid -z legacy-sa -n "$NS" >/dev/null
  oc set serviceaccount deployment/legacy legacy-sa -n "$NS" >/dev/null
  wait_deploy legacy "$NS" 180s
}
