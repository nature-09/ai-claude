# shellcheck shell=bash
EX_TITLE="NetworkPolicy 로 파드 간 통신 제어"
EX_SCOPE=namespace
NS="$U-np-app"
NSC="$U-np-client"
EX_NAMESPACES=("$NS" "$NSC")

ex_start() {
  ns_new "$NS"; ns_new "$NSC"
  app_deploy "$NS" web v1
  app_deploy "$NS" db v1
  oc set env deployment/db -n "$NS" APP_MESSAGE="I am db" >/dev/null
  app_route "$NS" web
  app_deploy "$NSC" client v1
  oc label namespace "$NSC" network=client --overwrite >/dev/null
  oc project "$NS" >/dev/null
  wait_deploy web "$NS"; wait_deploy db "$NS"; wait_deploy client "$NSC"
  info "현재는 모든 통신이 허용된 상태입니다. 가이드의 확인 명령으로 먼저 시험해 보세요"
}

ex_grade() {
  local web="http://web.$NS.svc:8080/" db="http://db.$NS.svc:8080/"
  section "정책"
  check "deny-all: 모든 파드의 Ingress 기본 차단" deny_all_ok
  check "allow-from-ingress 존재" res_exists "$NS" networkpolicy/allow-from-ingress
  check "allow-web-to-db 존재 (대상 app=db, 포트 8080)" webdb_policy_ok
  check "allow-client-to-web 존재" res_exists "$NS" networkpolicy/allow-client-to-web
  section "통신 시험"
  check "외부 → Route → web : 허용" route_has web "$NS" 'Hello from lab-app'
  check "web → db : 허용" pod_http_ok "$NS" web "$db"
  check "client($NSC) → web : 허용" pod_http_ok "$NSC" client "$web"
  check "client($NSC) → db : 차단" pod_http_blocked "$NSC" client "$db"
  check "db → web : 차단" pod_http_blocked "$NS" db "$web"
}
deny_all_ok() {
  jp_eq "$NS" networkpolicy/deny-all '{.spec.podSelector}' '{}' && jp_has "$NS" networkpolicy/deny-all '{.spec.policyTypes[*]}' Ingress &&
  [ -z "$(jp "$NS" networkpolicy/deny-all '{.spec.ingress}')" ]
}
webdb_policy_ok() {
  jp_eq "$NS" networkpolicy/allow-web-to-db '{.spec.podSelector.matchLabels.app}' db &&
  jp_has "$NS" networkpolicy/allow-web-to-db '{.spec.ingress[*].ports[*].port}' 8080
}

ex_solve() {
  oc apply -n "$NS" -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: deny-all}
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-from-ingress}
spec:
  podSelector: {matchLabels: {app: web}}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels: {policy-group.network.openshift.io/ingress: ""}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-web-to-db}
spec:
  podSelector: {matchLabels: {app: db}}
  ingress:
  - from:
    - podSelector: {matchLabels: {app: web}}
    ports:
    - {protocol: TCP, port: 8080}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-client-to-web}
spec:
  podSelector: {matchLabels: {app: web}}
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {network: client}}
    ports:
    - {protocol: TCP, port: 8080}
YAML
  sleep 5
}
