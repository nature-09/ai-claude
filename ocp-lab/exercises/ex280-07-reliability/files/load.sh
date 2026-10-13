#!/usr/bin/env bash
# HPA 부하 발생기: ./load.sh <route 호스트> [동시 요청 수] [초]
HOST="${1:?route 호스트를 지정하세요 (oc get route app -o jsonpath='{.spec.host}')}"
C="${2:-8}" T="${3:-180}"
end=$((SECONDS + T))
echo "부하 발생: http://$HOST/cpu?ms=500  동시 $C개, ${T}초 (Ctrl+C 로 중지)"
for _ in $(seq "$C"); do
  ( while [ $SECONDS -lt $end ]; do curl -s -m 5 -o /dev/null "http://$HOST/cpu?ms=500"; done ) &
done
wait
echo "부하 종료"
