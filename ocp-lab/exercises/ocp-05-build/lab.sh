# shellcheck shell=bash
EX_TITLE="이미지 스트림과 S2I 바이너리 빌드"
EX_SCOPE=namespace
NS="$U-build"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  copy_files
  oc project "$NS" >/dev/null
  local st; st="$(jp '' configs.imageregistry.operator.openshift.io/cluster '{.spec.managementState}')"
  [ "$st" = Managed ] || warn "내부 이미지 레지스트리 상태가 '$st' 입니다. 빌드 결과를 저장하려면 Managed 여야 합니다 (강사 확인)"
}

ex_grade() {
  check "ImageStream httpd-24 에 latest 태그 (사내 레지스트리에서 import)" jp_has "$NS" imagestream/httpd-24 '{.status.tags[*].tag}' 'latest'
  check "BuildConfig web 이 Source(S2I) 전략 + Binary 입력" bc_ok
  check "완료된 빌드가 2개 이상" builds_complete 2
  check "Deployment web 이 ImageStream 트리거를 가짐" jp_has "$NS" deployment/web '{.metadata.annotations.image\.openshift\.io/triggers}' 'web:latest'
  check "web 이 Ready" deploy_ready web "$NS"
  check "Route web 응답에 'version 2'" route_has web "$NS" 'version 2'
  check "Route web 응답에 owner $U" route_has web "$NS" "owner: $U"
}
bc_ok() {
  jp_eq "$NS" bc/web '{.spec.strategy.type}' Source && jp_eq "$NS" bc/web '{.spec.source.type}' Binary
}
builds_complete() {
  [ "$(oc get builds -n "$NS" -o jsonpath='{range .items[?(@.status.phase=="Complete")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c .)" -ge "$1" ]
}

ex_solve() {
  workdir
  oc import-image httpd-24:latest -n "$NS" --from="$IMG_HTTPD" --confirm >/dev/null || die "import-image 실패"
  res_exists "$NS" bc/web || oc new-build -n "$NS" --name=web --binary --image-stream=httpd-24:latest >/dev/null
  oc start-build web -n "$NS" --from-dir="$WORK/html" --wait >/dev/null || die "빌드 1 실패"
  res_exists "$NS" deployment/web || oc new-app -n "$NS" --image-stream=web:latest --name=web >/dev/null
  res_exists "$NS" route/web || oc expose service web -n "$NS" --port=8080 >/dev/null
  wait_deploy web "$NS"
  sed -i 's/version 1/version 2/' "$WORK/html/index.html"
  oc start-build web -n "$NS" --from-dir="$WORK/html" --wait >/dev/null || die "빌드 2 실패"
  sleep 5; wait_deploy web "$NS"
}
