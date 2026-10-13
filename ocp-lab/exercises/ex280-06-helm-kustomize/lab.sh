# shellcheck shell=bash
EX_TITLE="Helm 차트와 Kustomize 로 배포"
EX_SCOPE=namespace
NSH="$U-helm"
NSD="$U-kustomize-dev"
NSP="$U-kustomize-prod"
EX_NAMESPACES=("$NSH" "$NSD" "$NSP")

ex_start() {
  ns_new "$NSH"; ns_new "$NSD"; ns_new "$NSP"
  copy_files
  command -v helm >/dev/null 2>&1 || warn "helm 명령이 없습니다 (툴박스 사용 또는 bastion 에 helm 설치)"
  oc project "$NSH" >/dev/null
}

helm_rel() { # 배포된 릴리스의 리비전 (Helm 이 남기는 Secret 라벨에서 읽음)
  jp "$NSH" 'secret' '{range .items[?(@.metadata.labels.owner=="helm")]}{.metadata.labels.name} {.metadata.labels.status} {.metadata.labels.version}{"\n"}{end}' |
    awk -v n="$1" '$1==n && $2=="deployed" {print $3}'
}
ex_grade() {
  section "Helm"
  check "릴리스 web 이 deployed 상태" bash -c '[ -n "$1" ]' _ "$(helm_rel web)"
  check "릴리스 web 리비전 3 이상 (install → upgrade → rollback)" bash -c '[ "${1:-0}" -ge 3 ]' _ "$(helm_rel web)"
  check "web 레플리카 2 Ready" deploy_ready web "$NSH" 2
  check "web 이미지가 v1 (롤백 결과)" jp_has "$NSH" deployment/web '{.spec.template.spec.containers[0].image}' ':v1$'
  check "web 메시지 'Installed by Helm'" route_has web "$NSH" 'Installed by Helm'
  section "Kustomize"
  check "dev: kapp 레플리카 1 Ready, 이미지 v1" kapp_ok "$NSD" 1 v1
  check "dev: 메시지 dev" pod_exec_has "$NSD" kapp '^APP_MESSAGE=dev$' curl -s localhost:8080/env
  check "prod: kapp 레플리카 3 Ready, 이미지 v2" kapp_ok "$NSP" 3 v2
  check "prod: 메시지 prod" pod_exec_has "$NSP" kapp '^APP_MESSAGE=prod$' curl -s localhost:8080/env
  check "prod: ConfigMap 이름에 해시 접미어 (kapp-config-xxxx)" jp_has "$NSP" deployment/kapp '{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}' '^kapp-config-[a-z0-9]+$'
  check "prod: 라벨 env=prod" jp_eq "$NSP" deployment/kapp '{.metadata.labels.env}' prod
}
kapp_ok() { deploy_ready kapp "$1" "$2" && jp_eq "$1" deployment/kapp '{.spec.replicas}' "$2" && jp_has "$1" deployment/kapp '{.spec.template.spec.containers[0].image}' ":$3\$"; }

ex_solve() {
  workdir
  require_cmd helm
  helm upgrade --install web "$WORK/lab-web" -n "$NSH" --set replicaCount=2 --set message="Installed by Helm" >/dev/null
  helm upgrade web "$WORK/lab-web" -n "$NSH" --reuse-values --set image.tag=v2 --wait >/dev/null
  helm rollback web 1 -n "$NSH" --wait >/dev/null
  cat > "$WORK/kustomize/overlays/prod/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $NSP
resources:
- ../../base
labels:
- pairs:
    env: prod
replicas:
- name: kapp
  count: 3
images:
- name: lab-app
  newName: $IMG_APP
  newTag: v2
configMapGenerator:
- name: kapp-config
  behavior: merge
  literals:
  - APP_MESSAGE=prod
YAML
  oc apply -k "$WORK/kustomize/overlays/dev" >/dev/null
  oc apply -k "$WORK/kustomize/overlays/prod" >/dev/null
  wait_deploy kapp "$NSD"; wait_deploy kapp "$NSP"; wait_deploy web "$NSH"
}
