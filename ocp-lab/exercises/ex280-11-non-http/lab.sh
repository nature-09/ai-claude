# shellcheck shell=bash
EX_TITLE="HTTP 가 아닌 서비스 노출: NodePort, LoadBalancer(MetalLB)"
EX_SCOPE=namespace
NS="$U-tcp"
EX_NAMESPACES=("$NS")

has_metallb() { oc get ipaddresspools.metallb.io -A --no-headers 2>/dev/null | grep -q .; }

ex_start() {
  ns_new "$NS"
  oc create deployment echo -n "$NS" --image="$IMG_APP:v1" --port=9000 >/dev/null
  copy_files
  oc project "$NS" >/dev/null
  if has_metallb; then info "MetalLB 주소 풀이 있습니다. LoadBalancer 과제까지 진행하세요"
  else warn "MetalLB 가 구성되어 있지 않습니다. LoadBalancer 과제는 EXTERNAL-IP 가 <pending> 으로 남으며 채점에서 제외됩니다"; fi
}

node_ip() { oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null; }
ex_grade() {
  section "NodePort"
  check "Service echo-nodeport 유형 NodePort, 포트 9000" svc_is echo-nodeport NodePort
  check "nodePort 가 할당됨" jp_has "$NS" svc/echo-nodeport '{.spec.ports[0].nodePort}' '^3[0-9]{4}$'
  check "노드IP:nodePort 로 TCP echo 응답 (bastion → 노드)" tcp_has "$(node_ip)" "$(jp "$NS" svc/echo-nodeport '{.spec.ports[0].nodePort}')" 'lab-app tcp echo'
  section "LoadBalancer"
  check "Service echo-lb 유형 LoadBalancer, 포트 9000" svc_is echo-lb LoadBalancer
  if has_metallb; then
    check "EXTERNAL-IP 할당됨" jp_has "$NS" svc/echo-lb '{.status.loadBalancer.ingress[0].ip}' '.'
    check "EXTERNAL-IP:9000 으로 TCP echo 응답" tcp_has "$(jp "$NS" svc/echo-lb '{.status.loadBalancer.ingress[0].ip}')" 9000 'lab-app tcp echo'
  else
    skip "MetalLB 미구성 — EXTERNAL-IP 확인 생략"
  fi
}
svc_is() { jp_eq "$NS" "svc/$1" '{.spec.type}' "$2" && jp_eq "$NS" "svc/$1" '{.spec.ports[0].port}' 9000; }

ex_solve() {
  res_exists "$NS" svc/echo-nodeport || oc expose deployment echo -n "$NS" --name=echo-nodeport --type=NodePort --port=9000 --target-port=9000 >/dev/null
  res_exists "$NS" svc/echo-lb || oc expose deployment echo -n "$NS" --name=echo-lb --type=LoadBalancer --port=9000 --target-port=9000 >/dev/null
  wait_deploy echo "$NS"
  has_metallb && wait_until 60 jp_has "$NS" svc/echo-lb '{.status.loadBalancer.ingress[0].ip}' '.'
}
