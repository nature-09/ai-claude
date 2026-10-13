# shellcheck shell=bash
EX_TITLE="oc CLI와 웹 콘솔 기본, 프로젝트와 파드"
EX_SCOPE=namespace
NS="$U-cli"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_exists "$NS" && ns_del "$NS" && wait_until 120 ns_gone "$NS"
  workdir
  info "이번 실습은 프로젝트 $NS 를 직접 만드는 것부터 시작합니다"
  info "콘솔 주소: $(oc whoami --show-console 2>/dev/null)"
}
ns_gone() { ! ns_exists "$1"; }

ex_grade() {
  check "프로젝트 $NS 존재" ns_exists "$NS"
  check "프로젝트 표시 이름(display-name)이 'CLI 실습'" jp_eq '' "namespace/$NS" '{.metadata.annotations.openshift\.io/display-name}' "CLI 실습"
  check "프로젝트 설명(description) 입력됨" jp_has '' "namespace/$NS" '{.metadata.annotations.openshift\.io/description}' '.'
  check "네임스페이스 라벨 env=lab" jp_eq '' "namespace/$NS" '{.metadata.labels.env}' lab
  check "파드 hello 가 Running" jp_eq "$NS" pod/hello '{.status.phase}' Running
  check "파드 hello 이미지가 lab-app:v1" jp_has "$NS" pod/hello '{.spec.containers[0].image}' 'lab-app:v1$'
  check "파드 hello 에 라벨 tier=frontend" jp_eq "$NS" pod/hello '{.metadata.labels.tier}' frontend
  check "ConfigMap node-list(키 nodes.txt)에 노드 이름이 모두 기록됨" nodes_cm_ok
}
nodes_cm_ok() {
  local c n; c="$(jp "$NS" configmap/node-list '{.data.nodes\.txt}')"
  [ -n "$c" ] || return 1
  for n in $(oc get nodes -o jsonpath='{.items[*].metadata.name}'); do grep -q -- "$n" <<<"$c" || return 1; done
}

ex_solve() {
  workdir
  ns_exists "$NS" || oc new-project "$NS" --display-name="CLI 실습" --description="oc CLI 기본 실습" >/dev/null
  oc label namespace "$NS" env=lab --overwrite >/dev/null
  oc run hello -n "$NS" --image="$IMG_APP:v1" --labels=tier=frontend >/dev/null 2>&1 || true
  oc wait -n "$NS" pod/hello --for=condition=Ready --timeout=120s >/dev/null
  oc get nodes -o name > "$WORK/nodes.txt"
  oc create configmap node-list -n "$NS" --from-file="$WORK/nodes.txt" --dry-run=client -o yaml | oc apply -f - >/dev/null
}
