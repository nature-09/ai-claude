# shellcheck shell=bash
EX_TITLE="애플리케이션 배포, 서비스, 라우트, 스케일"
EX_SCOPE=namespace
NS="$U-deploy"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  oc project "$NS" >/dev/null
  info "현재 프로젝트를 $NS 로 바꿨습니다"
}

ex_grade() {
  check "Deployment web 존재" res_exists "$NS" deployment/web
  check "web 이미지가 lab-app:v1" jp_has "$NS" deployment/web '{.spec.template.spec.containers[0].image}' 'lab-app:v1$'
  check "web 환경 변수 APP_MESSAGE='Hello $U'" jp_eq "$NS" deployment/web '{.spec.template.spec.containers[0].env[?(@.name=="APP_MESSAGE")].value}' "Hello $U"
  check "web 레플리카 3개 Ready" deploy_ready web "$NS" 3
  check "Service web (8080) 존재" jp_has "$NS" service/web '{.spec.ports[*].port}' '8080'
  check "Service web 에 엔드포인트 3개" endpoints_n "$NS" web 3
  check "Route web 존재" res_exists "$NS" route/web
  check "Route 로 접속하면 'Hello $U' 응답" route_has web "$NS" "Hello $U"
}
endpoints_n() { [ "$(jp "$1" "endpoints/$2" '{.subsets[*].addresses[*].ip}' | wc -w)" -ge "$3" ]; }

ex_solve() {
  res_exists "$NS" deployment/web || oc create deployment web -n "$NS" --image="$IMG_APP:v1" --port=8080 >/dev/null
  oc set env deployment/web -n "$NS" APP_MESSAGE="Hello $U" >/dev/null
  res_exists "$NS" service/web || oc expose deployment web -n "$NS" --port=8080 >/dev/null
  res_exists "$NS" route/web || oc expose service web -n "$NS" >/dev/null
  oc scale deployment web -n "$NS" --replicas=3 >/dev/null
  wait_deploy web "$NS"
}
