# shellcheck shell=bash
EX_TITLE="ResourceQuota, LimitRange, ClusterResourceQuota"
EX_SCOPE=namespace
NS="$U-quota"
NS2="$U-quota2"
CRQ="$U-crq"
EX_NAMESPACES=("$NS" "$NS2")

ex_start() {
  ns_new "$NS"
  ns_new "$NS2"
  oc delete clusterresourcequota "$CRQ" --ignore-not-found >/dev/null
  copy_files
  oc project "$NS" >/dev/null
}

ex_grade() {
  section "ResourceQuota"
  local q="resourcequota/compute-quota"
  check "compute-quota: pods=10"            jp_eq "$NS" "$q" '{.spec.hard.pods}' 10
  check "compute-quota: requests.cpu=2"     jp_eq "$NS" "$q" '{.spec.hard.requests\.cpu}' 2
  check "compute-quota: requests.memory=2Gi" jp_eq "$NS" "$q" '{.spec.hard.requests\.memory}' 2Gi
  check "compute-quota: limits.cpu=4"       jp_eq "$NS" "$q" '{.spec.hard.limits\.cpu}' 4
  check "compute-quota: limits.memory=4Gi"  jp_eq "$NS" "$q" '{.spec.hard.limits\.memory}' 4Gi
  check "count-quota: services=5, secrets=20" count_quota_ok
  section "LimitRange"
  local c='{.spec.limits[?(@.type=="Container")]'
  check "default: cpu 500m / memory 512Mi"        lr_pair "$c.default" 500m 512Mi
  check "defaultRequest: cpu 100m / memory 128Mi" lr_pair "$c.defaultRequest" 100m 128Mi
  check "max: cpu 1 / memory 1Gi"                 lr_pair "$c.max" 1 1Gi
  section "배포"
  check "Deployment web 레플리카 12 로 설정" jp_eq "$NS" deployment/web '{.spec.replicas}' 12
  check "web 파드에 LimitRange 기본 requests(cpu 100m) 적용" jp_has "$NS" "pods" '{.items[*].spec.containers[0].resources.requests.cpu}' '100m'
  check "쿼터 때문에 파드가 10개로 제한됨" quota_capped
  section "ClusterResourceQuota"
  check "$CRQ: 라벨 quota-group=$U 인 프로젝트 선택" jp_eq '' "clusterresourcequota/$CRQ" '{.spec.selector.labels.matchLabels.quota-group}' "$U"
  check "$CRQ: pods=20, requests.cpu=4" crq_hard
  check "$CRQ 가 두 프로젝트($NS, $NS2)에 적용됨" crq_ns
}
count_quota_ok() { jp_eq "$NS" resourcequota/count-quota '{.spec.hard.services}' 5 && jp_eq "$NS" resourcequota/count-quota '{.spec.hard.secrets}' 20; }
lr_pair() { jp_eq "$NS" limitrange/default-limits "$1.cpu}" "$2" && jp_eq "$NS" limitrange/default-limits "$1.memory}" "$3"; }
quota_capped() {
  local n; n="$(oc get pods -n "$NS" -l app=web --no-headers 2>/dev/null | grep -vc -e Completed -e Terminating)"
  [ "$n" -le 10 ] && [ "$n" -ge 8 ] && jp_eq "$NS" resourcequota/compute-quota '{.status.used.pods}' 10
}
crq_hard() { jp_eq '' "clusterresourcequota/$CRQ" '{.spec.quota.hard.pods}' 20 && jp_eq '' "clusterresourcequota/$CRQ" '{.spec.quota.hard.requests\.cpu}' 4; }
crq_ns() {
  local s; s="$(jp '' "clusterresourcequota/$CRQ" '{.status.namespaces[*].namespace}')"
  grep -qw -- "$NS" <<<"$s" && grep -qw -- "$NS2" <<<"$s"
}

ex_solve() {
  oc create quota compute-quota -n "$NS" --hard=pods=10,requests.cpu=2,requests.memory=2Gi,limits.cpu=4,limits.memory=4Gi >/dev/null 2>&1
  oc create quota count-quota -n "$NS" --hard=services=5,secrets=20 >/dev/null 2>&1
  oc apply -n "$NS" -f - >/dev/null <<YAML
apiVersion: v1
kind: LimitRange
metadata: {name: default-limits}
spec:
  limits:
  - type: Container
    default: {cpu: 500m, memory: 512Mi}
    defaultRequest: {cpu: 100m, memory: 128Mi}
    max: {cpu: "1", memory: 1Gi}
YAML
  res_exists "$NS" deployment/web || oc create deployment web -n "$NS" --image="$IMG_APP:v1" >/dev/null
  oc scale deployment web -n "$NS" --replicas=12 >/dev/null
  oc label namespace "$NS" "$NS2" "quota-group=$U" --overwrite >/dev/null
  oc create clusterresourcequota "$CRQ" --project-label-selector="quota-group=$U" --hard=pods=20,requests.cpu=4 >/dev/null 2>&1
  sleep 20
}

ex_finish() {
  ns_del "$NS" "$NS2"
  oc delete clusterresourcequota "$CRQ" --ignore-not-found >/dev/null
}
