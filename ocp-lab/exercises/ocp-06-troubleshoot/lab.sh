# shellcheck shell=bash
EX_TITLE="장애 진단: 이미지·서비스·설정·프로브·스케줄링 문제 해결"
EX_SCOPE=namespace
NS="$U-trouble"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  apply_manifest broken.yaml
  oc project "$NS" >/dev/null
  info "고장 난 애플리케이션 5개를 배포했습니다. 'oc get pods' 로 확인하세요"
}

ex_grade() {
  check "app-image: 올바른 이미지(lab-app:v1)로 Ready" image_fixed
  check "app-svc: Route 로 접속 가능" route_has app-svc "$NS" 'Hello from lab-app'
  check "app-config: Secret app-db-secret(password) 생성, Ready" config_fixed
  check "app-probe: readiness 가 /readyz 로 수정되어 Ready" probe_fixed
  check "app-sched: CPU 요청을 줄여 Running(Ready)" deploy_ready app-sched "$NS"
}
image_fixed()  { jp_has "$NS" deployment/app-image '{.spec.template.spec.containers[0].image}' 'lab-app:v1$' && deploy_ready app-image "$NS"; }
config_fixed() { jp_has "$NS" secret/app-db-secret '{.data.password}' . && deploy_ready app-config "$NS"; }
probe_fixed()  { jp_eq "$NS" deployment/app-probe '{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' /readyz && deploy_ready app-probe "$NS"; }

ex_solve() {
  oc set image deployment/app-image -n "$NS" lab-app="$IMG_APP:v1" >/dev/null
  oc patch service app-svc -n "$NS" --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]' >/dev/null
  oc create secret generic app-db-secret -n "$NS" --from-literal=password=labpass >/dev/null 2>&1 || true
  oc set probe deployment/app-probe -n "$NS" --readiness --get-url=http://:8080/readyz --period-seconds=5 >/dev/null
  oc set resources deployment/app-sched -n "$NS" --requests=cpu=100m,memory=64Mi >/dev/null
  local d; for d in app-image app-config app-probe app-sched app-svc; do wait_deploy "$d" "$NS" 120s; done
}
