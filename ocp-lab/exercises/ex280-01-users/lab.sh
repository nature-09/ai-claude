# shellcheck shell=bash
EX_TITLE="HTPasswd ID 공급자와 사용자 관리"
EX_SCOPE=cluster
IDP="$U-htpasswd"
SECRET="$U-htpasswd"
EX_NAMESPACES=()

ex_start() {
  workdir
  local n; n="$(jp '' oauth/cluster '{.spec.identityProviders[*].name}')"
  info "현재 OAuth ID 공급자: ${n:-(없음)}"
  oauth_has_idp "$IDP" && warn "$IDP 가 이미 있습니다. 처음부터 하려면 'lab finish ex280-01' 후 다시 시작하세요"
  info "htpasswd 파일은 $WORK 에서 만드세요"
}

ex_grade() {
  check "openshift-config 에 Secret $SECRET (키 htpasswd)" jp_has openshift-config "secret/$SECRET" '{.data.htpasswd}' .
  check "OAuth 에 HTPasswd IdP '$IDP'" jp_eq '' oauth/cluster "{.spec.identityProviders[?(@.name==\"$IDP\")].type}" HTPasswd
  check "IdP '$IDP' 가 Secret $SECRET 를 사용" jp_eq '' oauth/cluster "{.spec.identityProviders[?(@.name==\"$IDP\")].htpasswd.fileData.name}" "$SECRET"
  check "$U-admin / redhat123 로그인 가능" login_ok "$U-admin" redhat123
  check "$U-dev / developer123 로그인 가능 (비밀번호 변경 반영)" login_ok "$U-dev" developer123
  check "$U-admin 에 cluster-admin 권한" can_i yes '*' '*' '' "$U-admin"
  check "$U-dev 는 cluster-admin 아님" can_i no delete nodes '' "$U-dev"
  check "$U-qa 가 htpasswd 에서 제거됨" qa_removed_from_file
  check "$U-qa 의 User/Identity 객체 삭제됨" qa_objects_removed
}
htpasswd_content() { jp openshift-config "secret/$SECRET" '{.data.htpasswd}' | base64 -d 2>/dev/null; }
qa_removed_from_file() { local c; c="$(htpasswd_content)"; [ -n "$c" ] && ! grep -q "^$U-qa:" <<<"$c"; }
qa_objects_removed() { res_absent '' "user/$U-qa" && res_absent '' "identity/$IDP:$U-qa"; }

ex_solve() {
  workdir
  local f="$WORK/users.htpasswd"
  { htpasswd_line "$U-admin" redhat123; htpasswd_line "$U-dev" developer123; } > "$f"
  oc create secret generic "$SECRET" -n openshift-config --from-file=htpasswd="$f" --dry-run=client -o yaml | oc apply -f - >/dev/null
  oauth_add_idp "$IDP" "$SECRET"
  oc adm policy add-cluster-role-to-user cluster-admin "$U-admin" >/dev/null 2>&1
  oc delete user "$U-qa" --ignore-not-found >/dev/null
  oc delete identity "$IDP:$U-qa" --ignore-not-found >/dev/null
  info "OAuth 서버 재시작을 기다립니다 (1~3분)"
  sleep 20
  oc rollout status deployment/oauth-openshift -n openshift-authentication --timeout=300s >/dev/null 2>&1 || true
  wait_until 180 login_ok "$U-dev" developer123 || warn "아직 로그인이 되지 않습니다. 잠시 후 lab grade 하세요"
}

ex_finish() {
  oauth_remove_idp "$IDP"
  oc delete secret "$SECRET" -n openshift-config --ignore-not-found >/dev/null
  oc adm policy remove-cluster-role-from-user cluster-admin "$U-admin" >/dev/null 2>&1 || true
  local u
  for u in admin dev qa; do
    oc delete user "$U-$u" --ignore-not-found >/dev/null
    oc delete identity "$IDP:$U-$u" --ignore-not-found >/dev/null
  done
}
