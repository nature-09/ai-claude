# shellcheck shell=bash
EX_TITLE="영구 스토리지: StorageClass, PVC, 볼륨 마운트"
EX_SCOPE=namespace
NS="$U-storage"
EX_NAMESPACES=("$NS")

ex_start() {
  ns_new "$NS"
  app_deploy "$NS" files v1
  # RWO 볼륨을 붙일 예정이므로 Recreate 전략으로 시작
  oc patch deployment files -n "$NS" -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' >/dev/null
  app_route "$NS" files
  oc project "$NS" >/dev/null
  echo; oc get storageclass
}

ex_grade() {
  check "PVC files-data 가 Bound" jp_eq "$NS" pvc/files-data '{.status.phase}' Bound
  check "PVC files-data 크기 1Gi 이상, RWO" pvc_ok
  check "PVC 가 기본(default) StorageClass 사용" pvc_default_sc
  check "files 에 PVC files-data 가 /data 로 마운트됨" mount_ok
  check "files 가 Ready" deploy_ready files "$NS"
  check "/data/hello.txt 내용이 '$U'" pod_exec_has "$NS" files "^$U\$" cat /data/hello.txt
  check "ConfigMap web-content 가 /data 가 아닌 /etc/app-config 에 마운트" jp_has "$NS" deployment/files '{.spec.template.spec.volumes[*].configMap.name}' web-content
  check "emptyDir 볼륨 cache 가 /cache 에 마운트" jp_has "$NS" deployment/files '{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cache")].mountPath}' '^/cache$'
}
pvc_ok() {
  local s; s="$(jp "$NS" pvc/files-data '{.status.capacity.storage}')"
  [[ "$s" =~ ^[1-9][0-9]*(Gi|Ti)$ ]] && jp_has "$NS" pvc/files-data '{.spec.accessModes[*]}' ReadWriteOnce
}
pvc_default_sc() {
  local def; def="$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')"
  [ -n "$def" ] && jp_eq "$NS" pvc/files-data '{.spec.storageClassName}' "$def"
}
mount_ok() {
  local vol; vol="$(jp "$NS" deployment/files '{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="files-data")].name}')"
  [ -n "$vol" ] && jp_eq "$NS" deployment/files "{.spec.template.spec.containers[0].volumeMounts[?(@.name==\"$vol\")].mountPath}" /data
}

ex_solve() {
  oc set volumes deployment/files -n "$NS" --add --name=data --type=pvc --claim-name=files-data \
    --claim-size=1Gi --claim-mode=rwo --mount-path=/data --overwrite >/dev/null
  oc create configmap web-content -n "$NS" --from-literal=index.html="hello $U" --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc set volumes deployment/files -n "$NS" --add --name=web --type=configmap --configmap-name=web-content --mount-path=/etc/app-config --overwrite >/dev/null
  oc set volumes deployment/files -n "$NS" --add --name=cache --type=emptyDir --mount-path=/cache --overwrite >/dev/null
  wait_deploy files "$NS" 300s || die "files 기동 실패"
  curl -s -m 10 -X POST --data-binary "$U" "http://$(route_host files "$NS")/data?file=hello.txt" >/dev/null
  oc delete pod -n "$NS" -l app=files >/dev/null
  wait_deploy files "$NS" 300s
}
