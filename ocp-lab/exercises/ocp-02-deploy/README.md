# ocp-02-deploy — 애플리케이션 배포, 서비스, 라우트, 스케일

## 목표
- 컨테이너 이미지로 Deployment 를 만든다 (`oc create deployment` / `oc new-app`)
- Service 와 Route 로 외부에 노출한다
- 환경 변수 변경과 스케일링, 롤링 업데이트를 관찰한다

## 시작
```bash
lab start ocp-02
eval "$(lab env)"
```
프로젝트 `${LAB_USER}-deploy` 가 만들어지고 현재 프로젝트로 설정됩니다.

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | Deployment 생성 | 이름 `web`, 이미지 `${IMG_APP}:v1`, 포트 8080 |
| 2 | 환경 변수 | `APP_MESSAGE=Hello ${LAB_USER}` |
| 3 | Service | 이름 `web`, 포트 8080 |
| 4 | Route | 이름 `web` (기본 호스트 이름 사용) |
| 5 | 스케일 | 레플리카 3개 |

<details><summary>힌트</summary>

```bash
oc create deployment web --image=${IMG_APP}:v1 --port=8080
# 또는: oc new-app --name=web --image=${IMG_APP}:v1   (Service 까지 자동 생성)
oc set env deployment/web APP_MESSAGE="Hello ${LAB_USER}"
oc expose deployment web --port=8080
oc expose service web
oc scale deployment web --replicas=3
```
</details>

## 확인해 볼 것
```bash
oc get deployment,replicaset,pod,svc,route
oc get endpoints web                           # 파드 IP 3개
HOST=$(oc get route web -o jsonpath='{.spec.host}')
for i in $(seq 6); do curl -s http://$HOST/; done   # 응답하는 파드(pod=...)가 바뀌는지
oc describe route web
oc get events --sort-by=.lastTimestamp | tail
```

### 롤링 업데이트 관찰
```bash
oc set env deployment/web APP_MESSAGE="Hello again"   # 템플릿이 바뀌면 새 ReplicaSet 생성
oc rollout status deployment/web
oc get rs                                             # 이전 RS 는 0 으로 줄어듦
oc set env deployment/web APP_MESSAGE="Hello ${LAB_USER}"   # 채점 조건으로 되돌리기
```

### 셀프 힐링
```bash
oc delete pod -l app=web --wait=false
oc get pods -w        # ReplicaSet 이 즉시 새 파드를 만듦 (Ctrl+C)
```

### 웹 콘솔
**Workloads → Deployments → web** 에서 레플리카 수 화살표로 스케일, **Topology** 화면에서 라우트 아이콘 클릭.

## 채점 / 정리
```bash
lab grade ocp-02
lab finish ocp-02
```
