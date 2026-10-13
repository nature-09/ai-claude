# shellcheck shell=bash
EX_TITLE="모의고사 (100점, 70점 이상 합격)"
EX_SCOPE=cluster
APPS="$U-exam-apps"
LEG="$U-exam-legacy"
IDP="$U-exam"
SECRET="$U-exam-htpasswd"
EX_NAMESPACES=("$APPS" "$LEG")

ex_start() {
  ns_new "$APPS"
  ns_new "$LEG"
  oc create deployment legacy -n "$LEG" --image="$IMG_APP:legacy" --port=80 >/dev/null
  oc expose deployment legacy -n "$LEG" --port=80 >/dev/null
  workdir
  rm -rf "${WORK:?}"/* && make_ca "$WORK"
  cp -r "$LAB_HOME/exercises/ex280-06-helm-kustomize/files/lab-web" "$WORK/"
  render "$LAB_HOME/exercises/ex280-06-helm-kustomize/files/lab-web/values.yaml" > "$WORK/lab-web/values.yaml"
  date +%s > "$WORK/.started"
  info "작업 디렉터리 $WORK : ca.crt, ca.key (사내 CA), lab-web (Helm 차트)"
  info "권장 시간 2시간. 시작 시각: $(date '+%H:%M')"
  info "문제: lab guide ex280-15"
}

d() { apps_domain; }
ex_grade() {
  local dom; dom="$(d)"; workdir
  if [ -f "$WORK/.started" ]; then info "경과 시간: $(( ($(date +%s) - $(cat "$WORK/.started")) / 60 ))분"; fi
  section "1. 인증 (10)"
  check -p 3 "IdP $IDP (HTPasswd, Secret $SECRET)" jp_eq '' oauth/cluster "{.spec.identityProviders[?(@.name==\"$IDP\")].htpasswd.fileData.name}" "$SECRET"
  check -p 4 "$U-alice / alice123 로그인" login_ok "$U-alice" alice123
  check -p 3 "$U-bob / bob123 로그인" login_ok "$U-bob" bob123
  section "2. 그룹·권한 (10)"
  check -p 2 "그룹 $U-leads ⊃ $U-alice" jp_has '' "group/$U-leads" '{.users[*]}' "(^| )$U-alice( |$)"
  check -p 2 "그룹 $U-devs ⊃ $U-bob" jp_has '' "group/$U-devs" '{.users[*]}' "(^| )$U-bob( |$)"
  check -p 3 "$U-leads: $APPS admin" can_i yes create rolebindings "$APPS" "$U-alice" "$U-leads"
  check -p 3 "$U-devs: $APPS edit (rolebinding 불가)" devs_edit
  section "3. 쿼터·LimitRange (10)"
  check -p 5 "exam-quota: pods=10, requests.cpu=2, requests.memory=2Gi" exam_quota
  check -p 5 "exam-limits: defaultRequest 100m/128Mi, default 300m/256Mi" exam_limits
  section "4. 애플리케이션 shop (15)"
  check -p 3 "shop: 이미지 v2, Ready 2개 이상" shop_basic
  check -p 4 "shop: ConfigMap shop-config 로 APP_MESSAGE='Exam shop'" shop_cm
  check -p 4 "shop: readiness /readyz, liveness /healthz" shop_probes
  check -p 4 "shop: requests cpu 200m (LimitRange 기본값 아님)" jp_eq "$APPS" deployment/shop '{.spec.template.spec.containers[0].resources.requests.cpu}' 200m
  section "5. 보안 라우트 (10)"
  check -p 4 "route shop: edge, 호스트 $U-shop.$dom" shop_route
  check -p 6 "https://$U-shop.$dom 가 사내 CA 인증서로 응답" https_verified_has "https://$U-shop.$dom/" 'Exam shop' "$WORK/ca.crt"
  section "6. HPA (5)"
  check -p 5 "hpa shop: 2~5, CPU 70%" shop_hpa
  section "7. 스토리지 (10)"
  check -p 4 "PVC shop-data Bound, 1Gi" jp_eq "$APPS" pvc/shop-data '{.status.phase}' Bound
  check -p 6 "shop 의 /data 에 shop-data 마운트" shop_pvc_mount
  section "8. 레거시 앱 (10)"
  check -p 4 "$LEG: legacy 가 SA legacy-sa 사용" jp_eq "$LEG" deployment/legacy '{.spec.template.spec.serviceAccountName}' legacy-sa
  check -p 6 "$LEG: legacy Ready (anyuid)" deploy_ready legacy "$LEG"
  section "9. 네트워크 정책 (10)"
  check -p 4 "$APPS: deny-all 정책" jp_eq "$APPS" networkpolicy/deny-all '{.spec.podSelector}' '{}'
  check -p 3 "라우트 접속은 허용됨 (위 5번과 동일 경로)" https_verified_has "https://$U-shop.$dom/" 'Exam shop' "$WORK/ca.crt"
  check -p 3 "$LEG 의 파드 → shop 차단" pod_http_blocked "$LEG" legacy "http://shop.$APPS.svc:8080/"
  section "10. CronJob (5)"
  check -p 5 "cronjob audit: '0 */6 * * *', 이미지 ubi" cron_ok
  section "11. Helm (5)"
  check -p 5 "helm 릴리스 promo: 레플리카 1, message 'Promo'" promo_ok
}
devs_edit() { can_i yes create deployments "$APPS" "$U-bob" "$U-devs" && can_i no create rolebindings "$APPS" "$U-bob" "$U-devs"; }
exam_quota() { local q=resourcequota/exam-quota; jp_eq "$APPS" $q '{.spec.hard.pods}' 10 && jp_eq "$APPS" $q '{.spec.hard.requests\.cpu}' 2 && jp_eq "$APPS" $q '{.spec.hard.requests\.memory}' 2Gi; }
exam_limits() {
  local c='{.spec.limits[?(@.type=="Container")]' l=limitrange/exam-limits
  jp_eq "$APPS" $l "$c.defaultRequest.cpu}" 100m && jp_eq "$APPS" $l "$c.defaultRequest.memory}" 128Mi &&
  jp_eq "$APPS" $l "$c.default.cpu}" 300m && jp_eq "$APPS" $l "$c.default.memory}" 256Mi
}
shop_basic() { jp_has "$APPS" deployment/shop '{.spec.template.spec.containers[0].image}' 'lab-app:v2$' && deploy_ready shop "$APPS" 2; }
shop_cm() { jp_eq "$APPS" configmap/shop-config '{.data.APP_MESSAGE}' 'Exam shop' && deploy_json_has shop "$APPS" '"name": "shop-config"'; }
shop_probes() {
  local c='{.spec.template.spec.containers[0]'
  jp_eq "$APPS" deployment/shop "$c.readinessProbe.httpGet.path}" /readyz && jp_eq "$APPS" deployment/shop "$c.livenessProbe.httpGet.path}" /healthz
}
shop_route() { jp_eq "$APPS" route/shop '{.spec.tls.termination}' edge && jp_eq "$APPS" route/shop '{.spec.host}' "$U-shop.$(d)"; }
shop_hpa() { jp_eq "$APPS" hpa/shop '{.spec.minReplicas}' 2 && jp_eq "$APPS" hpa/shop '{.spec.maxReplicas}' 5 && jp_eq "$APPS" hpa/shop '{.spec.metrics[0].resource.target.averageUtilization}' 70; }
shop_pvc_mount() {
  local v; v="$(jp "$APPS" deployment/shop '{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="shop-data")].name}')"
  [ -n "$v" ] && jp_eq "$APPS" deployment/shop "{.spec.template.spec.containers[0].volumeMounts[?(@.name==\"$v\")].mountPath}" /data
}
cron_ok() { jp_eq "$APPS" cronjob/audit '{.spec.schedule}' '0 */6 * * *' && jp_has "$APPS" cronjob/audit '{.spec.jobTemplate.spec.template.spec.containers[0].image}' 'ubi'; }
promo_ok() {
  jp "$APPS" secret '{range .items[?(@.metadata.labels.owner=="helm")]}{.metadata.labels.name} {.metadata.labels.status}{"\n"}{end}' | grep -q '^promo deployed$' &&
  jp_eq "$APPS" deployment/promo '{.spec.replicas}' 1 &&
  jp_eq "$APPS" deployment/promo '{.spec.template.spec.containers[0].env[?(@.name=="APP_MESSAGE")].value}' Promo
}

ex_solve() {
  local dom; dom="$(d)"; workdir
  # 1~2
  { htpasswd_line "$U-alice" alice123; htpasswd_line "$U-bob" bob123; } > "$WORK/exam.htpasswd"
  oc create secret generic "$SECRET" -n openshift-config --from-file=htpasswd="$WORK/exam.htpasswd" --dry-run=client -o yaml | oc apply -f - >/dev/null
  oauth_add_idp "$IDP" "$SECRET"
  oc adm groups new "$U-leads" "$U-alice" >/dev/null 2>&1 || true
  oc adm groups new "$U-devs" "$U-bob" >/dev/null 2>&1 || true
  oc policy add-role-to-group admin "$U-leads" -n "$APPS" >/dev/null
  oc policy add-role-to-group edit "$U-devs" -n "$APPS" >/dev/null
  # 3
  oc create quota exam-quota -n "$APPS" --hard=pods=10,requests.cpu=2,requests.memory=2Gi >/dev/null 2>&1
  oc apply -n "$APPS" -f - >/dev/null <<YAML
apiVersion: v1
kind: LimitRange
metadata: {name: exam-limits}
spec:
  limits:
  - type: Container
    defaultRequest: {cpu: 100m, memory: 128Mi}
    default: {cpu: 300m, memory: 256Mi}
YAML
  # 4
  oc create configmap shop-config -n "$APPS" --from-literal=APP_MESSAGE="Exam shop" >/dev/null 2>&1
  res_exists "$APPS" deployment/shop || oc create deployment shop -n "$APPS" --image="$IMG_APP:v2" --replicas=2 --port=8080 >/dev/null
  oc set env deployment/shop -n "$APPS" --from=configmap/shop-config >/dev/null
  oc set probe deployment/shop -n "$APPS" --readiness --get-url=http://:8080/readyz >/dev/null
  oc set probe deployment/shop -n "$APPS" --liveness --get-url=http://:8080/healthz >/dev/null
  oc set resources deployment/shop -n "$APPS" --requests=cpu=200m >/dev/null
  res_exists "$APPS" svc/shop || oc expose deployment shop -n "$APPS" --port=8080 >/dev/null
  # 7
  oc set volumes deployment/shop -n "$APPS" --add --name=data --type=pvc --claim-name=shop-data --claim-size=1Gi --mount-path=/data --overwrite >/dev/null
  oc patch deployment shop -n "$APPS" -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' >/dev/null
  # 5
  make_cert "$WORK" shop "$U-shop.$dom"
  oc delete route shop -n "$APPS" --ignore-not-found >/dev/null
  oc create route edge shop -n "$APPS" --service=shop --hostname="$U-shop.$dom" --cert="$WORK/shop.crt" --key="$WORK/shop.key" --ca-cert="$WORK/ca.crt" >/dev/null
  # 6
  res_exists "$APPS" hpa/shop || oc autoscale deployment/shop -n "$APPS" --min=2 --max=5 --cpu-percent=70 >/dev/null
  # 8
  oc create serviceaccount legacy-sa -n "$LEG" >/dev/null 2>&1 || true
  oc adm policy add-scc-to-user anyuid -z legacy-sa -n "$LEG" >/dev/null
  oc set serviceaccount deployment/legacy legacy-sa -n "$LEG" >/dev/null
  # 9
  oc apply -n "$APPS" -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: deny-all}
spec: {podSelector: {}, policyTypes: [Ingress]}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-ingress}
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {policy-group.network.openshift.io/ingress: ""}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-same-namespace}
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
YAML
  # 10
  res_exists "$APPS" cronjob/audit || oc create cronjob audit -n "$APPS" --image="$IMG_UBI" --schedule='0 */6 * * *' -- date >/dev/null
  # 11
  if command -v helm >/dev/null 2>&1; then
    helm upgrade --install promo "$WORK/lab-web" -n "$APPS" --set replicaCount=1 --set message=Promo --set route.enabled=false >/dev/null
  else warn "helm 이 없어 11번을 건너뜁니다"; fi
  wait_deploy shop "$APPS" 300s; wait_deploy legacy "$LEG" 180s
  info "OAuth 재시작 대기"; sleep 20
  wait_until 240 login_ok "$U-bob" bob123 || warn "로그인 확인 실패 — 잠시 후 채점하세요"
}

ex_finish() {
  oauth_remove_idp "$IDP"
  oc delete secret "$SECRET" -n openshift-config --ignore-not-found >/dev/null
  local u
  for u in alice bob; do
    oc delete user "$U-$u" --ignore-not-found >/dev/null
    oc delete identity "$IDP:$U-$u" --ignore-not-found >/dev/null
  done
  oc delete group "$U-leads" "$U-devs" --ignore-not-found >/dev/null
  ns_del "$APPS" "$LEG"
}
