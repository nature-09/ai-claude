#!/usr/bin/env bash
# TCP echo 시험: ./tcp-test.sh <호스트/IP> <포트>
# (nc 가 없어도 bash 의 /dev/tcp 로 접속)
H="${1:?호스트}" P="${2:?포트}"
if exec 3<>"/dev/tcp/$H/$P"; then
  timeout 3 head -n1 <&3
  echo "hello $(whoami)" >&3
  timeout 3 head -n1 <&3
  exec 3>&-
else
  echo "접속 실패: $H:$P"; exit 1
fi
