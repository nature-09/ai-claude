#!/usr/bin/env bash
# 백엔드/프론트엔드 컨테이너 이미지 빌드 (podman 우선, 없으면 docker)
#
# 사용 예)
#   ./scripts/build-images.sh                       # 인터넷 환경
#   VERSION=1.0.1 ./scripts/build-images.sh
#   BASE_REGISTRY=registry.corp.local:5000 \
#   MAVEN_MIRROR_URL=https://nexus.corp.local/repository/maven-public/ \
#   NPM_REGISTRY=https://nexus.corp.local/repository/npm-public/ \
#     ./scripts/build-images.sh                     # 폐쇄망 내부(Nexus) 빌드
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
IMAGE_PREFIX="${IMAGE_PREFIX:-messenger}"
BASE_REGISTRY="${BASE_REGISTRY:-registry.access.redhat.com}"
MAVEN_MIRROR_URL="${MAVEN_MIRROR_URL:-}"
NPM_REGISTRY="${NPM_REGISTRY:-}"
PLATFORM="${PLATFORM:-linux/amd64}"

if command -v podman >/dev/null 2>&1; then ENGINE=podman; else ENGINE=docker; fi
echo ">> container engine: $ENGINE, version: $VERSION, base registry: $BASE_REGISTRY"

$ENGINE build --platform "$PLATFORM" \
  --build-arg BUILDER_IMAGE="$BASE_REGISTRY/ubi9/openjdk-21:latest" \
  --build-arg RUNTIME_IMAGE="$BASE_REGISTRY/ubi9/openjdk-21-runtime:latest" \
  --build-arg MAVEN_MIRROR_URL="$MAVEN_MIRROR_URL" \
  -t "$IMAGE_PREFIX/messenger-backend:$VERSION" "$ROOT/backend"

$ENGINE build --platform "$PLATFORM" \
  --build-arg BUILDER_IMAGE="$BASE_REGISTRY/ubi9/nodejs-22:latest" \
  --build-arg RUNTIME_IMAGE="$BASE_REGISTRY/ubi9/nginx-124:latest" \
  --build-arg NPM_REGISTRY="$NPM_REGISTRY" \
  -t "$IMAGE_PREFIX/messenger-frontend:$VERSION" "$ROOT/frontend"

echo ">> 완료:"
echo "   $IMAGE_PREFIX/messenger-backend:$VERSION"
echo "   $IMAGE_PREFIX/messenger-frontend:$VERSION"
