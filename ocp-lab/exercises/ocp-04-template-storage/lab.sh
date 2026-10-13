# shellcheck shell=bash
EX_TITLE="템플릿으로 DB 배포, PVC 로 데이터 유지"
EX_SCOPE=namespace
NS="$U-db"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  copy_files
  oc project "$NS" >/dev/null
  local sc; sc="$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')"
  [ -n "$sc" ] && info "기본 StorageClass: $sc" || warn "기본 StorageClass 가 없습니다. PVC 가 Pending 이면 강사에게 문의하세요"
}

mysql_q() { # SQL
  oc exec -n "$NS" deploy/mysql -- bash -c "MYSQL_PWD=\"\$MYSQL_PASSWORD\" mysql -h127.0.0.1 -u\"\$MYSQL_USER\" \"\$MYSQL_DATABASE\" -N -e \"$1\"" 2>/dev/null
}

ex_grade() {
  check "템플릿 mysql-persistent-lab 이 프로젝트에 등록됨" res_exists "$NS" template/mysql-persistent-lab
  check "PVC mysql 이 Bound" jp_eq "$NS" pvc/mysql '{.status.phase}' Bound
  check "Secret mysql 의 사용자 labuser" jp_eq "$NS" secret/mysql '{.data.database-user}' "$(printf labuser | base64)"
  check "DB 이름 items" jp_eq "$NS" secret/mysql '{.data.database-name}' "$(printf items | base64)"
  check "mysql 이 Ready" deploy_ready mysql "$NS"
  check "products 테이블에 'persist-test' 행 존재" products_ok
  check "파드를 다시 만든 흔적 (현재 파드가 처음 파드가 아님)" pod_recreated
}
products_ok() { mysql_q 'select name from products' | grep -qx persist-test; }
# ReplicaSet 은 그대로인데 파드 이름이 처음 기록한 것과 다르면 재생성된 것
pod_recreated() {
  local first; first="$(jp "$NS" secret/mysql '{.metadata.annotations.lab/first-pod}')"
  local cur; cur="$(oc get pod -n "$NS" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [ -n "$first" ] && [ -n "$cur" ] && [ "$first" != "$cur" ]
}

ex_solve() {
  workdir
  oc create -n "$NS" -f "$WORK/mysql-persistent-template.yaml" >/dev/null 2>&1 || true
  oc process -n "$NS" mysql-persistent-lab -p MYSQL_USER=labuser -p MYSQL_PASSWORD=labpass -p MYSQL_DATABASE=items | oc apply -n "$NS" -f - >/dev/null
  wait_deploy mysql "$NS" 300s || die "mysql 기동 실패"
  mysql_q "create table if not exists products (id int auto_increment primary key, name varchar(50)); insert into products(name) values ('persist-test');" >/dev/null
  echo_first_pod
  oc delete pod -n "$NS" -l app=mysql --wait=true >/dev/null
  wait_deploy mysql "$NS" 300s
}
echo_first_pod() {
  oc annotate -n "$NS" secret/mysql "lab/first-pod=$(oc get pod -n "$NS" -l app=mysql -o jsonpath='{.items[0].metadata.name}')" --overwrite >/dev/null
}
