#!/usr/bin/env bash
# [인터넷 환경] 실습 이미지 빌드
#   - lab-app:v1, v2, v3(고장), legacy(root 필요)
#   - lab-toolbox:<VERSION>  (oc/kubectl/helm 포함 — mirror.openshift.com 에서 내려받음)
#
# 사용 예)
#   ./scripts/build-images.sh
#   OC_CHANNEL=stable-4.20 ./scripts/build-images.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
PREFIX="${LOCAL_PREFIX:-localhost/ocp-lab}"
PLATFORM="${PLATFORM:-linux/amd64}"
OC_CHANNEL="${OC_CHANNEL:-stable-4.19}"
OC_URL="${OC_URL:-https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$OC_CHANNEL/openshift-client-linux.tar.gz}"
HELM_URL="${HELM_URL:-https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64}"
GO_BUILDER="${GO_BUILDER:-registry.access.redhat.com/ubi9/go-toolset:latest}"
APP_RUNTIME="${APP_RUNTIME:-registry.access.redhat.com/ubi9/ubi-minimal:latest}"
TOOLBOX_BASE="${TOOLBOX_BASE:-registry.access.redhat.com/ubi9/ubi:latest}"

if command -v podman >/dev/null 2>&1; then ENGINE=podman; else ENGINE=docker; fi
echo ">> engine=$ENGINE version=$VERSION oc=$OC_CHANNEL"

# ---- oc / helm 클라이언트 (툴박스와 bastion 설치에 같이 사용)
CL="$ROOT/images/toolbox/clients"
mkdir -p "$CL"
if [ ! -s "$CL/openshift-client-linux.tar.gz" ] || [ "${REFRESH_CLIENTS:-false}" = true ]; then
  echo ">> download $OC_URL"
  curl -fL --retry 3 -o "$CL/openshift-client-linux.tar.gz" "$OC_URL"
fi
if [ ! -s "$CL/helm" ] || [ "${REFRESH_CLIENTS:-false}" = true ]; then
  echo ">> download $HELM_URL"
  curl -fL --retry 3 -o "$CL/helm" "$HELM_URL" && chmod +x "$CL/helm"
fi
echo "$OC_CHANNEL" > "$CL/OC_CHANNEL"

# ---- lab-app
build_app() { # tag [build-arg...]
  local tag="$1"; shift
  echo ">> build $PREFIX/lab-app:$tag"
  $ENGINE build --platform "$PLATFORM" \
    --build-arg BUILDER_IMAGE="$GO_BUILDER" --build-arg RUNTIME_IMAGE="$APP_RUNTIME" \
    "$@" -t "$PREFIX/lab-app:$tag" -f "$ROOT/images/lab-app/Containerfile" "$ROOT/images/lab-app"
}
build_app v1     --build-arg VERSION=v1
build_app v2     --build-arg VERSION=v2
build_app v3     --build-arg VERSION=v3 --build-arg BROKEN=true
build_app legacy --build-arg VERSION=legacy --build-arg APP_USER=0 --build-arg APP_PORT=80 --build-arg REQUIRE_ROOT=true

# ---- toolbox
echo ">> build $PREFIX/lab-toolbox:$VERSION"
$ENGINE build --platform "$PLATFORM" \
  --build-arg BASE_IMAGE="$TOOLBOX_BASE" --build-arg LAB_VERSION="$VERSION" \
  -t "$PREFIX/lab-toolbox:$VERSION" -f "$ROOT/images/toolbox/Containerfile" "$ROOT"

echo ">> 완료"
$ENGINE images --filter "reference=$PREFIX/*" 2>/dev/null || true
