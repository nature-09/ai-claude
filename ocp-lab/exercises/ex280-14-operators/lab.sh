# shellcheck shell=bash
EX_TITLE="OperatorHub/OLM 으로 오퍼레이터 설치 (CLI)"
EX_SCOPE=namespace
NS="$U-operator"
PKG="$LAB_OPERATOR_PACKAGE"
EX_NAMESPACES=("$NS")

pm() { jp openshift-marketplace "packagemanifest/$PKG" "$1"; }

ex_start() {
  oc get packagemanifest -n openshift-marketplace "$PKG" >/dev/null 2>&1 ||
    die "카탈로그에 '$PKG' 오퍼레이터가 없습니다. 강사에게 미러링/CatalogSource 를 확인하세요 (LAB_OPERATOR_PACKAGE 로 다른 오퍼레이터 지정 가능)"
  ns_new "$NS"
  oc project "$NS" >/dev/null
  local own; own="$(pm '{.status.channels[0].currentCSVDesc.installModes[?(@.type=="OwnNamespace")].supported}')"
  [ "$own" = true ] || warn "'$PKG' 가 OwnNamespace 설치를 지원하지 않을 수 있습니다 (공유 클러스터에서는 OwnNamespace 지원 오퍼레이터 권장)"
  info "설치할 오퍼레이터: $PKG"
  info "  카탈로그: $(pm '{.status.catalogSource}') ($(pm '{.status.catalogSourceNamespace}'))"
  info "  기본 채널: $(pm '{.status.defaultChannel}')"
}

csv_name() { jp "$NS" "subscription/$PKG" '{.status.installedCSV}'; }
ex_grade() {
  check "OperatorGroup 이 $NS 만 대상으로 (OwnNamespace)" og_ok
  check "Subscription $PKG 존재" res_exists "$NS" "subscription/$PKG"
  check "Subscription 이 패키지 카탈로그·채널을 올바르게 지정" sub_ok
  check "installPlanApproval=Manual" jp_eq "$NS" "subscription/$PKG" '{.spec.installPlanApproval}' Manual
  check "InstallPlan 이 승인됨" ip_approved
  check "CSV 가 Succeeded" csv_ok
  check "오퍼레이터 Deployment 가 Ready" op_deploy_ready
}
og_ok() {
  local n; n="$(oc get operatorgroup -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
  [ "$(wc -w <<<"$n")" -eq 1 ] && jp_eq "$NS" "operatorgroup/$n" '{.spec.targetNamespaces[*]}' "$NS"
}
sub_ok() {
  jp_eq "$NS" "subscription/$PKG" '{.spec.name}' "$PKG" &&
  jp_eq "$NS" "subscription/$PKG" '{.spec.source}' "$(pm '{.status.catalogSource}')" &&
  jp_eq "$NS" "subscription/$PKG" '{.spec.sourceNamespace}' openshift-marketplace &&
  jp_has "$NS" "subscription/$PKG" '{.spec.channel}' '.'
}
ip_approved() { jp "$NS" installplan '{.items[*].spec.approved}' | grep -qw true; }
csv_ok() { local c; c="$(csv_name)"; [ -n "$c" ] && jp_eq "$NS" "csv/$c" '{.status.phase}' Succeeded; }
op_deploy_ready() {
  local d x; d="$(oc get deploy -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
  [ -n "$d" ] || return 1
  for x in $d; do deploy_ready "$x" "$NS" || return 1; done
}

ex_solve() {
  local src ch
  src="$(pm '{.status.catalogSource}')"; ch="$(pm '{.status.defaultChannel}')"
  oc apply -n "$NS" -f - >/dev/null <<YAML
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata: {name: $NS-og}
spec:
  targetNamespaces: [$NS]
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: {name: $PKG}
spec:
  name: $PKG
  channel: $ch
  source: $src
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
YAML
  wait_until 180 jp_has "$NS" "subscription/$PKG" '{.status.installPlanRef.name}' '.' || die "InstallPlan 이 생성되지 않았습니다"
  local ip; ip="$(jp "$NS" "subscription/$PKG" '{.status.installPlanRef.name}')"
  oc patch installplan "$ip" -n "$NS" --type=merge -p '{"spec":{"approved":true}}' >/dev/null
  info "CSV 설치를 기다립니다 (수 분 소요)"
  wait_until 600 csv_ok || warn "CSV 가 아직 Succeeded 가 아닙니다"
}

ex_finish() {
  local c; c="$(csv_name)"
  oc delete subscription "$PKG" -n "$NS" --ignore-not-found >/dev/null 2>&1
  [ -n "$c" ] && oc delete csv "$c" -n "$NS" --ignore-not-found >/dev/null 2>&1
  ns_del "$NS"
  info "CRD 는 다른 수강생도 쓰므로 지우지 않습니다"
}
