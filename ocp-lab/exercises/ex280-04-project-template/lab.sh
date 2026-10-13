# shellcheck shell=bash
EX_TITLE="프로젝트 생성 템플릿 (기본 쿼터·LimitRange·NetworkPolicy)"
EX_SCOPE=cluster
TPL="$U-project-request"
TEST_NS="$U-tpl-test"
EX_NAMESPACES=("$TEST_NS")

ex_start() {
  workdir
  oc delete template "$TPL" -n openshift-config --ignore-not-found >/dev/null
  ns_exists "$TEST_NS" && ns_del "$TEST_NS"
  if is_shared; then
    info "공유 모드: 템플릿 작성·검증까지 채점합니다. 클러스터 적용(projects.config)은 강사 시연입니다"
  else
    info "단독 모드: 템플릿을 클러스터에 적용하고 새 프로젝트($TEST_NS)로 확인까지 채점합니다"
  fi
}

tpl_kind_n() { [ "$(jp openshift-config "template/$TPL" '{.objects[*].kind}' | tr ' ' '\n' | grep -cx "$1")" -ge "$2" ]; }
ex_grade() {
  section "템플릿 ($TPL, openshift-config)"
  check "Template $TPL 존재" res_exists openshift-config "template/$TPL"
  check "Project 객체 포함 (bootstrap 템플릿 기반)" tpl_kind_n Project 1
  check "ResourceQuota 포함" tpl_kind_n ResourceQuota 1
  check "LimitRange 포함" tpl_kind_n LimitRange 1
  check "NetworkPolicy 2개 이상 포함" tpl_kind_n NetworkPolicy 2
  check "PROJECT_NAME 파라미터로 이름이 정해지는 쿼터 (\${PROJECT_NAME}-quota)" jp_has openshift-config "template/$TPL" '{.objects[?(@.kind=="ResourceQuota")].metadata.name}' '\$\{PROJECT_NAME\}-quota'
  check "쿼터 pods=20, limits.memory=8Gi" tpl_quota_ok
  check "템플릿 처리(oc process) 성공" tpl_processes
  if is_shared; then
    section "클러스터 적용"
    skip "공유 클러스터 — projects.config 적용은 강사 시연 항목"
  else
    section "클러스터 적용"
    check "projects.config 가 $TPL 사용" jp_eq '' project.config.openshift.io/cluster '{.spec.projectRequestTemplate.name}' "$TPL"
    check "새 프로젝트 $TEST_NS 에 쿼터 자동 생성" res_exists "$TEST_NS" "resourcequota/$TEST_NS-quota"
    check "새 프로젝트 $TEST_NS 에 LimitRange 자동 생성" res_exists "$TEST_NS" "limitrange/$TEST_NS-limits"
    check "새 프로젝트 $TEST_NS 에 NetworkPolicy 자동 생성" netpol_n "$TEST_NS" 2
  fi
}
netpol_n() { [ "$(oc get networkpolicy -n "$1" --no-headers 2>/dev/null | wc -l)" -ge "$2" ]; }
tpl_quota_ok() {
  jp_eq openshift-config "template/$TPL" '{.objects[?(@.kind=="ResourceQuota")].spec.hard.pods}' 20 &&
  jp_eq openshift-config "template/$TPL" '{.objects[?(@.kind=="ResourceQuota")].spec.hard.limits\.memory}' 8Gi
}
tpl_processes() {
  oc process -n openshift-config "$TPL" -p PROJECT_NAME=x-test -p PROJECT_ADMIN_USER=x -p PROJECT_REQUESTING_USER=x -o name >/dev/null
}

ex_solve() {
  workdir
  local f="$WORK/project-template.yaml"
  oc adm create-bootstrap-project-template -o yaml > "$f"
  # bootstrap 템플릿은 objects 다음에 parameters 가 오므로 parameters 앞에 객체를 끼워 넣음
  sed -i "0,/^  name: project-request$/s//  name: $TPL/" "$f"
  local extra="$WORK/extra-objects.yaml"
  cat > "$extra" <<'YAML'
- apiVersion: v1
  kind: ResourceQuota
  metadata:
    name: ${PROJECT_NAME}-quota
    namespace: ${PROJECT_NAME}
  spec:
    hard:
      pods: "20"
      requests.cpu: "4"
      requests.memory: 8Gi
      limits.cpu: "8"
      limits.memory: 8Gi
- apiVersion: v1
  kind: LimitRange
  metadata:
    name: ${PROJECT_NAME}-limits
    namespace: ${PROJECT_NAME}
  spec:
    limits:
    - type: Container
      default: {cpu: 500m, memory: 512Mi}
      defaultRequest: {cpu: 100m, memory: 128Mi}
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-same-namespace
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    ingress:
    - from:
      - podSelector: {}
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-openshift-ingress
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            policy-group.network.openshift.io/ingress: ""
YAML
  awk -v extra="$extra" '/^parameters:/ && !done { while ((getline l < extra) > 0) print l; done=1 } {print}' "$f" > "$f.new" && mv "$f.new" "$f"
  oc apply -n openshift-config -f "$f" >/dev/null || die "템플릿 생성 실패"
  if ! is_shared; then
    oc patch project.config.openshift.io cluster --type=merge -p "{\"spec\":{\"projectRequestTemplate\":{\"name\":\"$TPL\"}}}" >/dev/null
    info "openshift-apiserver 재시작을 기다립니다 (1~3분)"
    sleep 30
    wait_until 240 new_test_project || warn "$TEST_NS 확인 실패"
    oc label namespace "$TEST_NS" "ocp-lab/student=$U" "ocp-lab/exercise=$EX_ID" --overwrite >/dev/null 2>&1
  fi
}

new_test_project() {
  ns_exists "$TEST_NS" || oc new-project "$TEST_NS" >/dev/null 2>&1
  res_exists "$TEST_NS" "resourcequota/$TEST_NS-quota" && return 0
  ns_del "$TEST_NS"; sleep 10; return 1
}

ex_finish() {
  if [ "$(jp '' project.config.openshift.io/cluster '{.spec.projectRequestTemplate.name}')" = "$TPL" ]; then
    info "projects.config 의 프로젝트 템플릿 설정을 해제합니다"
    oc patch project.config.openshift.io cluster --type=json -p '[{"op":"remove","path":"/spec/projectRequestTemplate"}]' >/dev/null
  fi
  oc delete template "$TPL" -n openshift-config --ignore-not-found >/dev/null
  ns_del "$TEST_NS"
}
