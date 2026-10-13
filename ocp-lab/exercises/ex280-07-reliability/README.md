# ex280-07-reliability — 프로브, 리소스, HPA

## 목표 (EX280: Configure applications for reliability)
- readiness / liveness (/ startup) 프로브를 설정하고 차이를 이해한다
- requests / limits 를 지정한다
- HorizontalPodAutoscaler 로 CPU 기반 자동 확장을 한다

## 시작
```bash
lab start ex280-07
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-07-reliability       # load.sh (부하 발생기)
```
`app` 은 기동 후 **20초** 동안 `/readyz` 가 503 을 돌려주도록 설정되어 있습니다 (`READY_DELAY=20`).
프로브가 없으면 준비되지 않은 파드로도 트래픽이 갑니다. 직접 확인해 보세요:
```bash
oc rollout restart deployment/app; HOST=$(oc get route app -o jsonpath='{.spec.host}')
for i in $(seq 10); do curl -s -o /dev/null -w '%{http_code} ' http://$HOST/readyz; sleep 2; done; echo
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | readiness | HTTP GET `/readyz` 8080, periodSeconds 5 |
| 2 | liveness | HTTP GET `/healthz` 8080, initialDelaySeconds 10, failureThreshold 3 |
| 3 | 리소스 | requests cpu 100m / memory 64Mi, limits cpu 500m / memory 256Mi |
| 4 | HPA | `app`, min 2, max 6, CPU 60% |
| 5 | 부하 | `load.sh` 로 부하를 주고 확장/축소 관찰 |
| 6 | liveness 시험 | 파드 하나에 `/fail-health` 호출 → 재시작 확인 |

<details><summary>힌트</summary>

```bash
oc set probe deployment/app --readiness --get-url=http://:8080/readyz --period-seconds=5
oc set probe deployment/app --liveness --get-url=http://:8080/healthz --initial-delay-seconds=10 --failure-threshold=3
oc set resources deployment/app --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=256Mi
oc autoscale deployment/app --min=2 --max=6 --cpu-percent=60
```
</details>

## 관찰
```bash
oc describe deployment app | grep -A3 -E 'Liveness|Readiness'
oc get hpa app -w                 # TARGETS 가 <unknown> 이면 requests.cpu 미설정 또는 metrics 문제
./load.sh $(oc get route app -o jsonpath='{.spec.host}') 8 180     # 다른 터미널에서
oc adm top pods
oc get pods -w

# liveness 실패 유도
POD=$(oc get pods -l app=app -o jsonpath='{.items[0].metadata.name}')
oc exec $POD -- curl -s localhost:8080/fail-health
oc get pod $POD -w                # 약 30초 뒤 RESTARTS 증가
oc describe pod $POD | grep -A10 Events     # "Liveness probe failed ... will be restarted"

# readiness 실패 유도 (재시작 없이 서비스에서만 빠짐)
oc exec $POD -- curl -s localhost:8080/toggle-ready
oc get endpoints app              # 해당 파드 IP 가 빠짐
oc exec $POD -- curl -s localhost:8080/toggle-ready
```

## 알아둘 것
- **readiness 실패** → 서비스 엔드포인트에서 제외 (재시작 X) / **liveness 실패** → 컨테이너 재시작
- **startup 프로브**: 기동이 느린 앱에서 liveness 가 너무 일찍 죽이지 않게 함 (`oc set probe --startup ...`)
- HPA 는 **requests** 대비 사용률로 계산합니다. requests.cpu 가 없으면 동작하지 않습니다.
- 메모리 limits 를 넘으면 OOMKilled, CPU limits 를 넘으면 스로틀링됩니다.
- YAML 로 만들기: `oc create -f` 로 `autoscaling/v2` HPA 를 작성할 수도 있습니다 (`oc explain hpa.spec.metrics`).

## 채점 / 정리
```bash
lab grade ex280-07
lab finish ex280-07
```
