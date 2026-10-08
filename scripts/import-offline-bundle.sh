#!/usr/bin/env bash
# [폐쇄망에서 실행] 반입한 이미지를 사내 레지스트리에 업로드
#
# 사용 예)
#   tar xzf messenger-offline-1.0.0.tar.gz && cd messenger-offline-1.0.0
#   podman login registry.corp.local:5000
#   REGISTRY=registry.corp.local:5000 ./import-offline-bundle.sh
#
#   # OpenShift 내부 레지스트리를 쓰는 경우 (route 노출 필요)
#   podman login -u $(oc whoami) -p $(oc whoami -t) default-route-openshift-image-registry.apps.<cluster>
#   REGISTRY=default-route-openshift-image-registry.apps.<cluster> NAMESPACE_PREFIX=messenger ./import-offline-bundle.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="${REGISTRY:?REGISTRY 환경변수에 사내 레지스트리 주소를 지정하세요 (예: registry.corp.local:5000)}"
TLS_VERIFY="${TLS_VERIFY:-true}"

if command -v podman >/dev/null 2>&1; then
  ENGINE=podman
  PUSH_OPTS="--tls-verify=$TLS_VERIFY"
else
  ENGINE=docker
  PUSH_OPTS=""
fi

( cd "$DIR/images" && sha256sum -c SHA256SUMS )

while read -r file source target; do
  [ -z "$file" ] && continue
  echo ">> load $file"
  $ENGINE load -i "$DIR/images/$file"
  dest="$REGISTRY/$target"
  echo ">> push $dest"
  $ENGINE tag "$source" "$dest"
  $ENGINE push $PUSH_OPTS "$dest"
done < "$DIR/images/images.txt"

cat <<MSG

==================================================================
이미지 업로드 완료. 다음 명령으로 설치하세요:

  oc new-project messenger   # 또는 기존 프로젝트 사용
  helm upgrade --install messenger ./helm-messenger -n messenger \\
    --set global.imageRegistry=$REGISTRY \\
    --set route.host=messenger.apps.<클러스터 도메인>

자세한 내용은 DEPLOY.md 참고
==================================================================
MSG
