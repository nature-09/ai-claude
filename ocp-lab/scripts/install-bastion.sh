#!/usr/bin/env bash
# [폐쇄망 bastion] lab 도구 설치 (root 로 실행)
#
#   sudo ./install-bastion.sh --registry registry.corp.local:5000 --api https://api.ocp.corp.local:6443
#
# 옵션
#   --registry <주소>     실습 이미지를 올린 레지스트리 (lab.env 의 LAB_REGISTRY)
#   --prefix <경로>       레지스트리 안 경로 (기본 ocp-lab)
#   --api <URL>           OCP API 주소 (lab login)
#   --shared true|false   여러 수강생 공유 여부 (기본 true)
#   --prefix-dir <경로>   설치 위치 (기본 /opt/ocp-lab)
#   --toolbox-only        lab 명령은 설치하지 않고 lab-shell(툴박스 실행기)과 설정만 설치
#   --force-clients       이미 oc/helm 이 있어도 번들의 클라이언트로 교체
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/ocp-lab"; [ -d "$SRC" ] || SRC="$(cd "$DIR/.." && pwd)"   # 번들 또는 저장소에서 실행
DEST=/opt/ocp-lab
REGISTRY="" PREFIX="ocp-lab" API="" SHARED="true" TOOLBOX_ONLY=false FORCE_CLIENTS=false

while [ $# -gt 0 ]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --api) API="$2"; shift 2 ;;
    --shared) SHARED="$2"; shift 2 ;;
    --prefix-dir) DEST="$2"; shift 2 ;;
    --toolbox-only) TOOLBOX_ONLY=true; shift ;;
    --force-clients) FORCE_CLIENTS=true; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done
[ "$(id -u)" -eq 0 ] || { echo "root 로 실행하세요 (sudo)" >&2; exit 1; }

echo ">> $SRC → $DEST"
rm -rf "$DEST.new" && mkdir -p "$DEST.new"
cp -r "$SRC/bin" "$SRC/lib" "$SRC/VERSION" "$SRC/lab.env.example" "$DEST.new/"
[ -d "$SRC/exercises" ] && cp -r "$SRC/exercises" "$DEST.new/"
[ -d "$SRC/docs" ] && cp -r "$SRC/docs" "$DEST.new/"
[ -d "$SRC/mirror" ] && cp -r "$SRC/mirror" "$DEST.new/"
rm -rf "$DEST" && mv "$DEST.new" "$DEST"
chmod 0755 "$DEST"/bin/*

ln -sf "$DEST/bin/lab-shell" /usr/local/bin/lab-shell
if [ "$TOOLBOX_ONLY" = false ]; then
  ln -sf "$DEST/bin/lab" /usr/local/bin/lab
  ln -sf "$DEST/bin/lab-admin" /usr/local/bin/lab-admin
  comp="$SRC/lab-completion.bash"; [ -f "$comp" ] || comp="$SRC/images/toolbox/lab-completion.bash"
  [ -f "$comp" ] && install -m 0644 "$comp" /etc/bash_completion.d/lab
fi

# oc / kubectl / helm
CL="$DIR/clients"; [ -d "$CL" ] || CL="$SRC/images/toolbox/clients"
if [ -f "$CL/openshift-client-linux.tar.gz" ] && { ! command -v oc >/dev/null 2>&1 || [ "$FORCE_CLIENTS" = true ]; }; then
  echo ">> oc, kubectl 설치 → /usr/local/bin"
  tar xzf "$CL/openshift-client-linux.tar.gz" -C /usr/local/bin oc kubectl
fi
if [ -f "$CL/helm" ] && { ! command -v helm >/dev/null 2>&1 || [ "$FORCE_CLIENTS" = true ]; }; then
  echo ">> helm 설치 → /usr/local/bin"
  install -m 0755 "$CL/helm" /usr/local/bin/helm
fi

# 설정 파일
mkdir -p /etc/ocp-lab
if [ ! -f /etc/ocp-lab/lab.env ]; then
  cp "$DEST/lab.env.example" /etc/ocp-lab/lab.env
  echo ">> /etc/ocp-lab/lab.env 생성"
fi
setkv() { # key value
  [ -n "$2" ] || return 0
  if grep -q "^$1=" /etc/ocp-lab/lab.env; then sed -i "s|^$1=.*|$1=$2|" /etc/ocp-lab/lab.env
  else echo "$1=$2" >> /etc/ocp-lab/lab.env; fi
}
setkv LAB_REGISTRY "$REGISTRY"
setkv LAB_REPO_PREFIX "$PREFIX"
setkv LAB_API_URL "$API"
setkv LAB_SHARED "$SHARED"
chmod 0644 /etc/ocp-lab/lab.env

cat > /etc/profile.d/ocp-lab.sh <<PROFILE
# ocp-lab
export LAB_HOME=$DEST
PROFILE

echo ">> 필요한 패키지 확인"
missing=()
for c in jq openssl curl htpasswd podman; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "   없음: ${missing[*]}"
  echo "   설치 예: dnf install -y jq openssl curl httpd-tools podman skopeo   (사내 RHEL 미러 저장소)"
else
  echo "   OK"
fi

cat <<MSG

==================================================================
설치 완료 (ocp-lab $(cat "$DEST/VERSION"))
  설정: /etc/ocp-lab/lab.env  ← LAB_REGISTRY / LAB_API_URL 확인
  강사: lab-admin check  →  lab-admin students create 20
  수강생 (호스트에서 직접):  lab init student01 → lab login → lab list
  수강생 (툴박스 컨테이너):  lab-shell
==================================================================
MSG
