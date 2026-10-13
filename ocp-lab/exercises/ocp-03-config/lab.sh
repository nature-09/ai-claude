# shellcheck shell=bash
EX_TITLE="ConfigMap 과 Secret 으로 설정 주입 (환경 변수, 볼륨)"
EX_SCOPE=namespace
NS="$U-config"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  app_deploy "$NS" app v1
  app_route "$NS" app
  copy_files
  oc project "$NS" >/dev/null
  wait_deploy app "$NS" || warn "app 이 아직 준비되지 않았습니다 (oc get pods 확인)"
}

ex_grade() {
  check "ConfigMap app-config 에 APP_MESSAGE, APP_COLOR" cm_keys
  check "Secret app-secret (Opaque) 에 DB_PASSWORD" jp_has "$NS" secret/app-secret '{.data.DB_PASSWORD}' '.'
  check "ConfigMap app-files 에 app.properties" jp_has "$NS" configmap/app-files '{.data.app\.properties}' "lab.owner=$U"
  check "Deployment app 이 app-config 를 환경 변수로 사용" deploy_json_has app "$NS" '"name": "app-config"'
  check "Deployment app 이 app-secret 을 환경 변수로 사용" deploy_json_has app "$NS" '"name": "app-secret"'
  check "app-files 가 /etc/app-config 에 마운트됨" jp_has "$NS" deployment/app '{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' '/etc/app-config'
  check "app 이 Ready" deploy_ready app "$NS"
  check "앱 /env 에 APP_MESSAGE=Configured by ConfigMap" route_has app "$NS" '^APP_MESSAGE=Configured by ConfigMap$' /env
  check "앱 /env 에 DB_PASSWORD=r3dh4t123" route_has app "$NS" '^DB_PASSWORD=r3dh4t123$' /env
  check "앱 /config 에 app.properties 내용" route_has app "$NS" "lab.owner=$U" /config
}
cm_keys() {
  jp_eq "$NS" configmap/app-config '{.data.APP_MESSAGE}' "Configured by ConfigMap" &&
  jp_eq "$NS" configmap/app-config '{.data.APP_COLOR}' blue
}

ex_solve() {
  workdir
  oc create configmap app-config -n "$NS" --from-literal=APP_MESSAGE="Configured by ConfigMap" --from-literal=APP_COLOR=blue --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc create secret generic app-secret -n "$NS" --from-literal=DB_PASSWORD=r3dh4t123 --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc create configmap app-files -n "$NS" --from-file="$WORK/app.properties" --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc set env deployment/app -n "$NS" --from=configmap/app-config >/dev/null
  oc set env deployment/app -n "$NS" --from=secret/app-secret >/dev/null
  oc set volume deployment/app -n "$NS" --add --name=app-files --type=configmap --configmap-name=app-files --mount-path=/etc/app-config --overwrite >/dev/null
  wait_deploy app "$NS"
}
