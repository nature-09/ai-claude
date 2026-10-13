#!/usr/bin/env bash
# [인터넷 환경] 폐쇄망 반입 번들 생성
#   1) 실습 이미지 빌드 (scripts/build-images.sh)
#   2) 실습에 쓰는 Red Hat 이미지 pull (registry.redhat.io 로그인 필요: podman login registry.redhat.io)
#   3) 이미지 tar + lab 도구 + oc/helm 클라이언트 + 설치/업로드 스크립트를 하나로 묶음
#
# 결과물: dist/ocp-lab-bundle-<VERSION>.tar.gz
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
PREFIX="${LOCAL_PREFIX:-localhost/ocp-lab}"
PLATFORM="${PLATFORM:-linux/amd64}"
SKIP_BUILD="${SKIP_BUILD:-false}"
UBI_IMAGE="${UBI_IMAGE:-registry.access.redhat.com/ubi9/ubi:latest}"
HTTPD_IMAGE="${HTTPD_IMAGE:-registry.access.redhat.com/ubi9/httpd-24:latest}"
MYSQL_IMAGE="${MYSQL_IMAGE:-registry.redhat.io/rhel9/mysql-80:latest}"

if command -v podman >/dev/null 2>&1; then ENGINE=podman; else ENGINE=docker; fi
NAME="ocp-lab-bundle-$VERSION"
OUT="$ROOT/dist/$NAME"
rm -rf "$OUT" && mkdir -p "$OUT/images" "$OUT/clients"

[ "$SKIP_BUILD" = true ] || VERSION="$VERSION" "$ROOT/scripts/build-images.sh"

echo ">> 베이스 이미지 pull"
for img in "$UBI_IMAGE" "$HTTPD_IMAGE" "$MYSQL_IMAGE"; do $ENGINE pull --platform "$PLATFORM" "$img"; done

# 파일명  원본 이미지  레지스트리 안의 대상(<prefix>/ 아래)
cat > "$OUT/images/images.txt" <<LIST
lab-app-v1.tar      $PREFIX/lab-app:v1                lab-app:v1
lab-app-v2.tar      $PREFIX/lab-app:v2                lab-app:v2
lab-app-v3.tar      $PREFIX/lab-app:v3                lab-app:v3
lab-app-legacy.tar  $PREFIX/lab-app:legacy            lab-app:legacy
lab-toolbox.tar     $PREFIX/lab-toolbox:$VERSION      lab-toolbox:$VERSION
ubi9-ubi.tar        $UBI_IMAGE                        ubi9-ubi:latest
ubi9-httpd-24.tar   $HTTPD_IMAGE                      ubi9-httpd-24:latest
rhel9-mysql-80.tar  $MYSQL_IMAGE                      rhel9-mysql-80:latest
LIST

while read -r file src _; do
  [ -z "$file" ] && continue
  echo ">> save $src -> images/$file"
  $ENGINE save -o "$OUT/images/$file" "$src"
done < "$OUT/images/images.txt"
( cd "$OUT/images" && sha256sum ./*.tar > SHA256SUMS )

echo ">> lab 도구 복사"
mkdir -p "$OUT/ocp-lab"
cp -r "$ROOT/bin" "$ROOT/lib" "$ROOT/exercises" "$ROOT/docs" "$ROOT/mirror" "$ROOT/VERSION" "$ROOT/lab.env.example" "$OUT/ocp-lab/"
cp "$ROOT/images/toolbox/lab-completion.bash" "$OUT/ocp-lab/lab-completion.bash"
cp "$ROOT/images/toolbox/clients/openshift-client-linux.tar.gz" "$ROOT/images/toolbox/clients/helm" "$OUT/clients/"
cp "$ROOT/scripts/import-bundle.sh" "$ROOT/scripts/install-bastion.sh" "$OUT/"
cp "$ROOT/README.md" "$OUT/README.md"

echo ">> 압축"
tar -C "$ROOT/dist" -czf "$ROOT/dist/$NAME.tar.gz" "$NAME"
( cd "$ROOT/dist" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )
du -h "$ROOT/dist/$NAME.tar.gz"
echo ">> 완료: dist/$NAME.tar.gz (+ .sha256)"
