#!/usr/bin/env bash
# [폐쇄망 bastion] 번들의 이미지를 사내 레지스트리에 올림
#
#   tar xzf ocp-lab-bundle-<ver>.tar.gz && cd ocp-lab-bundle-<ver>
#   podman login registry.corp.local:5000
#   REGISTRY=registry.corp.local:5000 ./import-bundle.sh
#
# 환경 변수
#   REGISTRY     사내 레지스트리 (없으면 /etc/ocp-lab/lab.env 의 LAB_REGISTRY)
#   PREFIX       레지스트리 안의 경로 (기본 ocp-lab, lab.env 의 LAB_REPO_PREFIX 와 같아야 함)
#   TLS_VERIFY   true/false (기본 true)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${REGISTRY:-}" ] && [ -r /etc/ocp-lab/lab.env ]; then
  REGISTRY="$(sed -n 's/^LAB_REGISTRY=\([^ #]*\).*/\1/p' /etc/ocp-lab/lab.env | tail -1)"
  PREFIX="${PREFIX:-$(sed -n 's/^LAB_REPO_PREFIX=\([^ #]*\).*/\1/p' /etc/ocp-lab/lab.env | tail -1)}"
fi
REGISTRY="${REGISTRY:?REGISTRY 환경 변수에 사내 레지스트리를 지정하세요 (예: registry.corp.local:5000)}"
PREFIX="${PREFIX:-ocp-lab}"
TLS_VERIFY="${TLS_VERIFY:-true}"

echo ">> 체크섬 확인"
( cd "$DIR/images" && sha256sum -c SHA256SUMS )

while read -r file src target; do
  [ -z "$file" ] && continue
  dest="$REGISTRY/$PREFIX/$target"
  echo ">> $file -> $dest"
  if command -v skopeo >/dev/null 2>&1; then
    skopeo copy --dest-tls-verify="$TLS_VERIFY" "docker-archive:$DIR/images/$file" "docker://$dest"
  else
    podman load -i "$DIR/images/$file" >/dev/null
    podman tag "$src" "$dest"
    podman push --tls-verify="$TLS_VERIFY" "$dest"
  fi
done < "$DIR/images/images.txt"

cat <<MSG

==================================================================
업로드 완료: $REGISTRY/$PREFIX/
  ※ 클러스터 노드가 이 경로의 이미지를 pull 할 수 있어야 합니다.
     - 레지스트리 CA 가 클러스터에 신뢰되어 있는지 (image.config additionalTrustedCA)
     - 저장소가 public 이거나 글로벌 pull secret 에 인증 정보가 있는지
다음 단계:
  sudo ./install-bastion.sh --registry $REGISTRY --prefix $PREFIX --api https://api.<cluster>:6443
  lab-admin check
==================================================================
MSG
