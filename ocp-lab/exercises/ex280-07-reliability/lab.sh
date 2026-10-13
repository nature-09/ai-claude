# shellcheck shell=bash
EX_TITLE="프로브, 리소스 requests/limits, HPA 로 안정성 확보"
EX_SCOPE=namespace
NS="$U-reliability"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  app_deploy "$NS" app v1
  oc set env deployment/app -n "$NS" READY_DELAY=20 >/dev/null
  app_route "$NS" app
  copy_files
  oc project "$NS" >/dev/null
  oc get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1 || warn "metrics API 가 없습니다. HPA 가 동작하지 않을 수 있습니다"
}

c0='{.spec.template.spec.containers[0]'
ex_grade() {
  section "프로브"
  check "readiness: HTTP GET /readyz :8080" probe_ok readinessProbe /readyz
  check "readiness: periodSeconds=5" jp_eq "$NS" deployment/app "$c0.readinessProbe.periodSeconds}" 5
  check "liveness: HTTP GET /healthz :8080" probe_ok livenessProbe /healthz
  check "liveness: initialDelaySeconds=10, failureThreshold=3" liveness_params
  section "리소스"
  check "requests cpu=100m, memory=64Mi" res_pair requests 100m 64Mi
  check "limits cpu=500m, memory=256Mi" res_pair limits 500m 256Mi
  section "HPA"
  check "HPA app: min 2 / max 6" hpa_minmax
  check "HPA app: CPU 목표 60%" jp_eq "$NS" hpa/app '{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}' 60
  check "app 이 2개 이상 Ready" deploy_ready app "$NS" 2
  check "HPA 가 현재 CPU 사용률을 읽고 있음 (metrics 정상)" jp_has "$NS" hpa/app '{.status.currentMetrics[*].resource.current.averageUtilization}' '^[0-9]+'
  section "liveness 동작 확인"
  check "liveness 실패로 컨테이너가 재시작된 적 있음 (/fail-health 실습)" restarted
}
probe_ok() { jp_eq "$NS" deployment/app "$c0.$1.httpGet.path}" "$2" && jp_eq "$NS" deployment/app "$c0.$1.httpGet.port}" 8080; }
liveness_params() { jp_eq "$NS" deployment/app "$c0.livenessProbe.initialDelaySeconds}" 10 && jp_eq "$NS" deployment/app "$c0.livenessProbe.failureThreshold}" 3; }
res_pair() { jp_eq "$NS" deployment/app "$c0.resources.$1.cpu}" "$2" && jp_eq "$NS" deployment/app "$c0.resources.$1.memory}" "$3"; }
hpa_minmax() { jp_eq "$NS" hpa/app '{.spec.minReplicas}' 2 && jp_eq "$NS" hpa/app '{.spec.maxReplicas}' 6; }
restarted() { jp "$NS" pods '{.items[*].status.containerStatuses[*].restartCount}' | tr ' ' '\n' | grep -qv '^0$'; }

ex_solve() {
  oc set probe deployment/app -n "$NS" --readiness --get-url=http://:8080/readyz --period-seconds=5 >/dev/null
  oc set probe deployment/app -n "$NS" --liveness --get-url=http://:8080/healthz --initial-delay-seconds=10 --failure-threshold=3 >/dev/null
  oc set resources deployment/app -n "$NS" --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=256Mi >/dev/null
  res_exists "$NS" hpa/app || oc autoscale deployment/app -n "$NS" --min=2 --max=6 --cpu-percent=60 >/dev/null
  wait_deploy app "$NS" 240s
  local pod; pod="$(oc get pods -n "$NS" -l app=app -o jsonpath='{.items[0].metadata.name}')"
  oc exec -n "$NS" "$pod" -- curl -s localhost:8080/fail-health >/dev/null
  info "liveness 실패 → 재시작을 기다립니다 (약 40초)"
  wait_until 120 restarted
}
