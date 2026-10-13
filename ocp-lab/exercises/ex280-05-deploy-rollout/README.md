# ex280-05-deploy-rollout — 배포 전략, 롤아웃/롤백, 이미지 스트림 태그와 digest

## 목표 (EX280: Deploy applications / Manage application updates)
- 롤링 업데이트 전략을 조정하고 새 버전으로 롤아웃한다
- 고장 난 버전을 배포했을 때 롤백한다
- 태그 대신 **digest** 로 이미지를 고정한다
- ImageStream 태그를 옮겨서(`oc tag`) 자동 재배포되게 한다

## 이미지
| 태그 | 내용 |
|---|---|
| `${IMG_APP}:v1` | 정상, version=v1 |
| `${IMG_APP}:v2` | 정상, version=v2 |
| `${IMG_APP}:v3` | 기동하자마자 종료하는 **고장 버전** |

## 시작
```bash
lab start ex280-05
eval "$(lab env)"
```

## Part 1. Deployment 롤아웃과 롤백

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 배포 | Deployment `myapp`, `${IMG_APP}:v1`, 레플리카 3, Service/Route `myapp` (8080) |
| 2 | 전략 | RollingUpdate `maxSurge=1`, `maxUnavailable=0` |
| 3 | 업데이트 | v2 로 변경, 완료 확인 |
| 4 | 장애 배포 | v3 로 변경 → 롤아웃이 멈추는 것 확인 |
| 5 | 롤백 | 직전 버전(v2)으로 되돌리기 |
| 6 | digest 고정 | `myapp` 이미지를 v2 의 **digest**(`...lab-app@sha256:...`)로 지정 |

```bash
oc create deployment myapp --image=${IMG_APP}:v1 --replicas=3 --port=8080
oc expose deployment myapp --port=8080 && oc expose service myapp
oc patch deployment myapp -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
oc describe deployment myapp | grep -i strategy

oc set image deployment/myapp lab-app=${IMG_APP}:v2       # 컨테이너 이름은 lab-app
oc annotate deployment/myapp kubernetes.io/change-cause="v2 배포" --overwrite
oc rollout status deployment/myapp

oc set image deployment/myapp lab-app=${IMG_APP}:v3
oc rollout status deployment/myapp --timeout=60s          # 진행되지 않음
oc get pods                                               # CrashLoopBackOff, 기존 v2 파드는 그대로 유지 (maxUnavailable=0)
oc logs deploy/myapp                                      # FATAL 메시지
oc rollout history deployment/myapp
oc rollout undo deployment/myapp                          # 또는 --to-revision=N
```

### digest 확인 방법
```bash
# 방법 A: 실행 중인 파드의 imageID
oc get pod -l app=myapp -o jsonpath='{.items[0].status.containerStatuses[0].imageID}{"\n"}'
# 방법 B: ImageStream 으로 가져와서 확인 (Part 2 에서 함께)
oc import-image lab-app:v2 --from=${IMG_APP}:v2 --confirm
oc get istag lab-app:v2 -o jsonpath='{.image.dockerImageReference}{"\n"}'
# 방법 C (bastion): skopeo inspect docker://${IMG_APP}:v2 | jq -r .Digest

oc set image deployment/myapp lab-app=<레지스트리>/.../lab-app@sha256:<digest>
```
태그(`:v2`)는 나중에 다른 이미지를 가리킬 수 있지만 digest 는 항상 같은 이미지입니다.

## Part 2. ImageStream 태그와 자동 재배포

| # | 할 일 | 조건 |
|---|---|---|
| 7 | ImageStream | `lab-app` 에 `v1`, `v2` 태그 import |
| 8 | prod 태그 | `lab-app:prod` → v1 |
| 9 | 배포 | `lab-app:prod` 로 Deployment `myapp-is` (이미지 트리거 포함) |
| 10 | 승격 | `lab-app:prod` → v2 로 옮겨 `myapp-is` 가 자동 재배포되게 |

```bash
oc import-image lab-app:v1 --from=${IMG_APP}:v1 --confirm
oc import-image lab-app:v2 --from=${IMG_APP}:v2 --confirm
oc tag lab-app:v1 lab-app:prod
oc get is lab-app; oc get istag

oc new-app --image-stream=lab-app:prod --name=myapp-is    # 트리거 어노테이션 자동 생성
oc get deployment myapp-is -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}{"\n"}'
# 이미 만든 Deployment 에 트리거 추가: oc set triggers deployment/<이름> --from-image=lab-app:prod -c <컨테이너>

oc tag lab-app:v2 lab-app:prod                             # 승격 → 자동 롤아웃
oc rollout status deployment/myapp-is
oc exec deploy/myapp-is -- curl -s localhost:8080/
```

### 더 해보기
- 주기적 import: `oc tag ${IMG_APP}:v2 lab-app:latest --scheduled` (사내 레지스트리에서 태그가 바뀌면 자동 반영)
- `oc tag --alias`, `oc tag -d lab-app:prod` 의 차이
- 웹 콘솔 **Builds → ImageStreams** 에서 태그 이력 확인

## 채점 / 정리
```bash
lab grade ex280-05
lab finish ex280-05
```
