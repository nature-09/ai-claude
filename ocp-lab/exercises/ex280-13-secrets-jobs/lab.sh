# shellcheck shell=bash
EX_TITLE="Secret 주입, 서비스 어카운트 권한, Job/CronJob"
EX_SCOPE=namespace
NS="$U-jobs"
EX_NAMESPACES=("$NS")
SA_FULL="system:serviceaccount:$NS:report-sa"

ex_start() {
  ns_new "$NS"
  app_deploy "$NS" api v1
  oc set env deployment/api -n "$NS" REQUIRED_ENV=API_USER,API_TOKEN >/dev/null
  copy_files
  oc project "$NS" >/dev/null
  info "api 는 API_USER, API_TOKEN 환경 변수가 없으면 기동하지 않습니다"
}

ex_grade() {
  section "Secret"
  check "Secret api-creds: API_USER=labuser" jp_eq "$NS" secret/api-creds '{.data.API_USER}' "$(printf labuser | base64)"
  check "Secret api-creds: API_TOKEN=s3cr3t-token" jp_eq "$NS" secret/api-creds '{.data.API_TOKEN}' "$(printf s3cr3t-token | base64)"
  check "api 가 Secret 을 환경 변수로 사용 (값을 직접 쓰지 않음)" api_uses_secret
  check "api 가 Ready" deploy_ready api "$NS"
  section "서비스 어카운트"
  check "ServiceAccount report-sa 존재" res_exists "$NS" sa/report-sa
  check "report-sa: 파드 조회 가능 (view)" can_i yes list pods "$NS" "$SA_FULL"
  check "report-sa: 파드 삭제 불가" can_i no delete pods "$NS" "$SA_FULL"
  section "CronJob / Job"
  check "CronJob report: 스케줄 */2 * * * *" jp_eq "$NS" cronjob/report '{.spec.schedule}' '*/2 * * * *'
  check "CronJob report: report-sa 사용" jp_eq "$NS" cronjob/report '{.spec.jobTemplate.spec.template.spec.serviceAccountName}' report-sa
  check "CronJob report: REPORT_USER 를 Secret 에서 가져옴" jp_eq "$NS" cronjob/report '{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="REPORT_USER")].valueFrom.secretKeyRef.name}' api-creds
  check "Job report-manual 성공" jp_eq "$NS" job/report-manual '{.status.succeeded}' 1
  check "report-manual 로그에 파드 목록과 'report by labuser'" job_log_ok
}
api_uses_secret() {
  deploy_json_has api "$NS" '"name": "api-creds"' && ! deploy_json_has api "$NS" 's3cr3t-token'
}
job_log_ok() {
  local l; l="$(oc logs -n "$NS" job/report-manual 2>/dev/null)"
  grep -q 'report by labuser' <<<"$l" && grep -q 'pod/api' <<<"$l"
}

ex_solve() {
  workdir
  oc create secret generic api-creds -n "$NS" --from-literal=API_USER=labuser --from-literal=API_TOKEN=s3cr3t-token --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc set env deployment/api -n "$NS" --from=secret/api-creds >/dev/null
  oc create serviceaccount report-sa -n "$NS" >/dev/null 2>&1 || true
  oc policy add-role-to-user view -z report-sa -n "$NS" >/dev/null
  sed -e 's|schedule: ""                      # TODO: 2분마다|schedule: "*/2 * * * *"|' \
      -e 's|serviceAccountName: ""    # TODO: report-sa|serviceAccountName: report-sa|' \
      -e 's|              value: ""|              valueFrom: {secretKeyRef: {name: api-creds, key: API_USER}}|' \
      "$WORK/cronjob.yaml" | oc apply -n "$NS" -f - >/dev/null || die "CronJob 생성 실패"
  wait_deploy api "$NS"
  oc delete job report-manual -n "$NS" --ignore-not-found >/dev/null
  oc create job report-manual -n "$NS" --from=cronjob/report >/dev/null
  oc wait -n "$NS" job/report-manual --for=condition=complete --timeout=180s >/dev/null || warn "Job 완료 대기 시간 초과"
}
