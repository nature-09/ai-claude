#!/usr/bin/env bash
# [인터넷 환경에서 실행] 폐쇄망 반입용 번들 생성
#   - 앱 이미지 빌드
#   - PostgreSQL / Redis 이미지 pull (registry.redhat.io 로그인 필요: podman login registry.redhat.io)
#   - 이미지 tar 저장 + Helm 차트 패키징 + 반입 스크립트 동봉
#
# 결과물: dist/messenger-offline-<VERSION>.tar.gz
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
IMAGE_PREFIX="${IMAGE_PREFIX:-messenger}"
PLATFORM="${PLATFORM:-linux/amd64}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-registry.redhat.io/rhel9/postgresql-16:latest}"
REDIS_IMAGE="${REDIS_IMAGE:-registry.redhat.io/rhel9/redis-7:latest}"
SKIP_BUILD="${SKIP_BUILD:-false}"

if command -v podman >/dev/null 2>&1; then ENGINE=podman; else ENGINE=docker; fi
OUT="$ROOT/dist/messenger-offline-$VERSION"
rm -rf "$OUT" && mkdir -p "$OUT/images"

if [ "$SKIP_BUILD" != "true" ]; then
  VERSION="$VERSION" IMAGE_PREFIX="$IMAGE_PREFIX" PLATFORM="$PLATFORM" "$ROOT/scripts/build-images.sh"
fi

echo ">> 인프라 이미지 pull"
$ENGINE pull --platform "$PLATFORM" "$POSTGRES_IMAGE"
$ENGINE pull --platform "$PLATFORM" "$REDIS_IMAGE"

save() {
  local image="$1" file="$2"
  echo ">> save $image -> images/$file"
  $ENGINE save -o "$OUT/images/$file" "$image"
}
save "$IMAGE_PREFIX/messenger-backend:$VERSION"  messenger-backend.tar
save "$IMAGE_PREFIX/messenger-frontend:$VERSION" messenger-frontend.tar
save "$POSTGRES_IMAGE" postgresql.tar
save "$REDIS_IMAGE"    redis.tar

cat > "$OUT/images/images.txt" <<LIST
messenger-backend.tar  $IMAGE_PREFIX/messenger-backend:$VERSION   $IMAGE_PREFIX/messenger-backend:$VERSION
messenger-frontend.tar $IMAGE_PREFIX/messenger-frontend:$VERSION  $IMAGE_PREFIX/messenger-frontend:$VERSION
postgresql.tar         $POSTGRES_IMAGE  rhel9/postgresql-16:latest
redis.tar              $REDIS_IMAGE     rhel9/redis-7:latest
LIST

echo ">> Helm 차트 복사"
cp -r "$ROOT/helm/messenger" "$OUT/helm-messenger"
if command -v helm >/dev/null 2>&1; then
  helm package "$ROOT/helm/messenger" -d "$OUT" >/dev/null
fi

cp "$ROOT/scripts/import-offline-bundle.sh" "$OUT/"
cp "$ROOT/docs/DEPLOY.md" "$OUT/" 2>/dev/null || true
( cd "$OUT/images" && sha256sum *.tar > SHA256SUMS )

echo ">> 압축"
tar -C "$ROOT/dist" -czf "$ROOT/dist/messenger-offline-$VERSION.tar.gz" "messenger-offline-$VERSION"
echo ">> 완료: dist/messenger-offline-$VERSION.tar.gz"
