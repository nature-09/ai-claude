# shellcheck shell=bash
EX_TITLE="배포 전략, 롤아웃/롤백, 이미지 스트림 태그와 digest"
EX_SCOPE=namespace
NS="$U-rollout"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  oc project "$NS" >/dev/null
}

v2_digest() { jp "$NS" istag/lab-app:v2 '{.image.metadata.name}'; }
ex_grade() {
  section "myapp (Deployment 롤아웃)"
  check "myapp 레플리카 3 Ready" deploy_ready myapp "$NS" 3
  check "롤링 업데이트 maxUnavailable=0, maxSurge=1" strategy_ok
  check "롤아웃 이력(ReplicaSet) 3개 이상 (v1→v2→v3→롤백)" rs_n 3
  check "v3(고장 버전) 파드가 남아 있지 않음" no_v3
  check "myapp 이미지가 digest(@sha256) 로 고정됨" jp_has "$NS" deployment/myapp '{.spec.template.spec.containers[0].image}' '@sha256:'
  check "myapp 이 v2 로 응답" route_has myapp "$NS" 'version=v2'
  section "ImageStream / 트리거"
  check "ImageStream lab-app 에 v1, v2 태그" is_tags_ok
  check "lab-app:prod 가 v2 와 같은 이미지" prod_is_v2
  check "myapp-is 에 이미지 트리거(lab-app:prod)" jp_has "$NS" deployment/myapp-is '{.metadata.annotations.image\.openshift\.io/triggers}' 'lab-app:prod'
  check "myapp-is 가 v2 로 동작 (태그 변경으로 자동 재배포)" pod_exec_has "$NS" myapp-is 'version=v2' curl -s localhost:8080/
}
strategy_ok() {
  jp_eq "$NS" deployment/myapp '{.spec.strategy.rollingUpdate.maxUnavailable}' 0 &&
  jp_eq "$NS" deployment/myapp '{.spec.strategy.rollingUpdate.maxSurge}' 1
}
rs_n() { [ "$(oc get rs -n "$NS" -l app=myapp --no-headers 2>/dev/null | wc -l)" -ge "$1" ]; }
no_v3() { ! oc get pods -n "$NS" -l app=myapp -o jsonpath='{.items[*].spec.containers[*].image}' | grep -q 'lab-app:v3'; }
is_tags_ok() { local t; t="$(jp "$NS" is/lab-app '{.status.tags[*].tag}')"; grep -qw v1 <<<"$t" && grep -qw v2 <<<"$t"; }
prod_is_v2() {
  local p v; p="$(jp "$NS" istag/lab-app:prod '{.image.metadata.name}')"; v="$(v2_digest)"
  [ -n "$p" ] && [ "$p" = "$v" ]
}

ex_solve() {
  if ! res_exists "$NS" deployment/myapp; then
    oc create deployment myapp -n "$NS" --image="$IMG_APP:v1" --replicas=3 --port=8080 >/dev/null
    oc expose deployment myapp -n "$NS" --port=8080 >/dev/null
    oc expose service myapp -n "$NS" >/dev/null
  fi
  oc patch deployment myapp -n "$NS" -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}' >/dev/null
  wait_deploy myapp "$NS"
  oc set image deployment/myapp -n "$NS" lab-app="$IMG_APP:v2" >/dev/null; wait_deploy myapp "$NS"
  oc set image deployment/myapp -n "$NS" lab-app="$IMG_APP:v3" >/dev/null
  oc rollout status deployment/myapp -n "$NS" --timeout=40s >/dev/null 2>&1 || true
  oc rollout undo deployment/myapp -n "$NS" >/dev/null; wait_deploy myapp "$NS"
  oc import-image lab-app:v1 -n "$NS" --from="$IMG_APP:v1" --confirm >/dev/null
  oc import-image lab-app:v2 -n "$NS" --from="$IMG_APP:v2" --confirm >/dev/null
  local ref; ref="$(jp "$NS" istag/lab-app:v2 '{.image.dockerImageReference}')"
  oc set image deployment/myapp -n "$NS" lab-app="$ref" >/dev/null; wait_deploy myapp "$NS"
  oc tag -n "$NS" lab-app:v1 lab-app:prod >/dev/null
  res_exists "$NS" deployment/myapp-is || oc new-app -n "$NS" --image-stream=lab-app:prod --name=myapp-is >/dev/null
  wait_deploy myapp-is "$NS"
  oc tag -n "$NS" lab-app:v2 lab-app:prod >/dev/null
  sleep 10; wait_deploy myapp-is "$NS"
}
