# shellcheck shell=bash
EX_TITLE="그룹과 RBAC (역할 바인딩, 사용자 정의 Role, self-provisioner)"
EX_SCOPE=namespace
DEV="$U-rbac-dev"
PROD="$U-rbac-prod"
GDEV="$U-developers"
GQA="$U-qa-team"
EX_NAMESPACES=("$DEV" "$PROD")

ex_start() {
  ns_new "$DEV"
  ns_new "$PROD"
  oc delete group "$GDEV" "$GQA" --ignore-not-found >/dev/null
  is_shared && info "공유 모드: self-provisioner 제거(과제 6)는 강사 시연으로 진행하며 채점하지 않습니다"
}

ex_grade() {
  section "그룹"
  check "그룹 $GDEV 에 $U-dev" jp_has '' "group/$GDEV" '{.users[*]}' "(^| )$U-dev( |$)"
  check "그룹 $GQA 에 $U-qa" jp_has '' "group/$GQA" '{.users[*]}' "(^| )$U-qa( |$)"
  section "역할 바인딩"
  check "$GDEV: $DEV 에서 edit (디플로이먼트 생성 가능)" can_i yes create deployments "$DEV" "$U-dev" "$GDEV"
  check "$GDEV: $DEV 에서 rolebinding 생성 불가 (admin 아님)" can_i no create rolebindings "$DEV" "$U-dev" "$GDEV"
  check "$GDEV: $PROD 접근 불가" can_i no get pods "$PROD" "$U-dev" "$GDEV"
  check "$GQA: $DEV 조회 가능(view)" can_i yes list pods "$DEV" "$U-qa" "$GQA"
  check "$GQA: $PROD 조회 가능(view)" can_i yes list pods "$PROD" "$U-qa" "$GQA"
  check "$GQA: $PROD 수정 불가" can_i no delete pods "$PROD" "$U-qa" "$GQA"
  check "$U-admin: $PROD 의 admin (rolebinding 생성 가능)" can_i yes create rolebindings "$PROD" "$U-admin"
  section "사용자 정의 Role / 서비스 어카운트"
  check "$PROD 에 Role pod-reader" res_exists "$PROD" role/pod-reader
  check "SA monitor: $PROD 파드 조회 가능" can_i yes list pods "$PROD" "system:serviceaccount:$PROD:monitor"
  check "SA monitor: $PROD 파드 삭제 불가" can_i no delete pods "$PROD" "system:serviceaccount:$PROD:monitor"
  check "SA monitor: $PROD 시크릿 조회 불가" can_i no get secrets "$PROD" "system:serviceaccount:$PROD:monitor"
  section "self-provisioner"
  if is_shared; then
    skip "공유 클러스터 — 강사 시연 항목 (self-provisioner 제거)"
  else
    check "system:authenticated:oauth 의 self-provisioner 권한 제거" self_prov_removed
    check "self-provisioners 바인딩 autoupdate=false" jp_eq '' clusterrolebinding/self-provisioners '{.metadata.annotations.rbac\.authorization\.kubernetes\.io/autoupdate}' false
  fi
}
self_prov_removed() { ! jp '' clusterrolebinding/self-provisioners '{.subjects[*].name}' | grep -q 'system:authenticated:oauth'; }

ex_solve() {
  oc adm groups new "$GDEV" "$U-dev" >/dev/null 2>&1 || oc adm groups add-users "$GDEV" "$U-dev" >/dev/null
  oc adm groups new "$GQA" "$U-qa" >/dev/null 2>&1 || oc adm groups add-users "$GQA" "$U-qa" >/dev/null
  oc policy add-role-to-group edit "$GDEV" -n "$DEV" >/dev/null
  oc policy add-role-to-group view "$GQA" -n "$DEV" >/dev/null
  oc policy add-role-to-group view "$GQA" -n "$PROD" >/dev/null
  oc policy add-role-to-user admin "$U-admin" -n "$PROD" >/dev/null 2>&1
  oc create role pod-reader -n "$PROD" --verb=get,list,watch --resource=pods >/dev/null 2>&1 || true
  oc create serviceaccount monitor -n "$PROD" >/dev/null 2>&1 || true
  oc policy add-role-to-user pod-reader -z monitor -n "$PROD" --role-namespace="$PROD" >/dev/null
  if ! is_shared; then
    oc annotate clusterrolebinding self-provisioners rbac.authorization.kubernetes.io/autoupdate=false --overwrite >/dev/null
    oc patch clusterrolebinding self-provisioners --type=json -p '[{"op":"remove","path":"/subjects"}]' >/dev/null 2>&1 || true
  fi
}

ex_finish() {
  ns_del "$DEV" "$PROD"
  oc delete group "$GDEV" "$GQA" --ignore-not-found >/dev/null
  if ! is_shared && self_prov_removed; then
    info "self-provisioner 권한을 원래대로 복구합니다"
    oc adm policy add-cluster-role-to-group self-provisioner system:authenticated:oauth >/dev/null 2>&1
    oc annotate clusterrolebinding self-provisioners rbac.authorization.kubernetes.io/autoupdate=true --overwrite >/dev/null 2>&1
  fi
}
