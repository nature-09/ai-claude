# ex280-03-quota-limits — ResourceQuota, LimitRange, ClusterResourceQuota

## 목표 (EX280: Enable developer self-service)
- 프로젝트 단위 자원 쿼터와 객체 수 쿼터를 만든다
- LimitRange 로 컨테이너 기본 requests/limits 와 최대값을 정한다
- 여러 프로젝트에 걸친 ClusterResourceQuota 를 만든다
- 쿼터 초과 시 어떤 현상이 나타나는지 확인한다

## 시작
```bash
lab start ex280-03
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-03-quota-limits      # limitrange.yaml 뼈대
```
프로젝트 `${LAB_USER}-quota`, `${LAB_USER}-quota2` 가 준비됩니다.

## 과제 (`${LAB_USER}-quota` 기준)

| # | 할 일 | 조건 |
|---|---|---|
| 1 | ResourceQuota `compute-quota` | pods=10, requests.cpu=2, requests.memory=2Gi, limits.cpu=4, limits.memory=4Gi |
| 2 | ResourceQuota `count-quota` | services=5, secrets=20 |
| 3 | LimitRange `default-limits` (Container) | default: cpu 500m, memory 512Mi / defaultRequest: cpu 100m, memory 128Mi / max: cpu 1, memory 1Gi |
| 4 | 배포 | Deployment `web` (`${IMG_APP}:v1`, 리소스 지정 없이) 를 만들고 레플리카 12 로 스케일 |
| 5 | ClusterResourceQuota `${LAB_USER}-crq` | 라벨 `quota-group=${LAB_USER}` 인 프로젝트들 합계 pods=20, requests.cpu=4 |
| 6 | 라벨 | 두 프로젝트에 `quota-group=${LAB_USER}` 라벨 |

> 순서가 중요합니다. compute-quota 처럼 cpu/memory 쿼터가 있는 프로젝트에서는 requests/limits 가 없는 파드가 **거부**됩니다.
> LimitRange 를 먼저 만들어 기본값이 들어가게 한 뒤 배포하세요.

<details><summary>힌트</summary>

```bash
oc create quota compute-quota --hard=pods=10,requests.cpu=2,requests.memory=2Gi,limits.cpu=4,limits.memory=4Gi
oc create quota count-quota --hard=services=5,secrets=20
vi limitrange.yaml && oc apply -f limitrange.yaml
oc create deployment web --image=${IMG_APP}:v1
oc scale deployment web --replicas=12

oc label namespace ${LAB_USER}-quota ${LAB_USER}-quota2 quota-group=${LAB_USER}
oc create clusterresourcequota ${LAB_USER}-crq \
   --project-label-selector=quota-group=${LAB_USER} --hard=pods=20,requests.cpu=4
```
</details>

## 확인
```bash
oc describe quota                        # Used / Hard
oc describe limitrange default-limits
oc get pod -l app=web -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'   # 자동으로 들어간 값
oc get pods                              # 10개만 생성됨
oc get events | grep -i quota            # "exceeded quota: compute-quota"
oc describe rs -l app=web | grep -A3 Events
oc describe clusterresourcequota ${LAB_USER}-crq
oc describe AppliedClusterResourceQuota -n ${LAB_USER}-quota2   # 프로젝트 관리자 시점
```

## 더 해보기
- max 를 넘는 요청: `oc set resources deployment/web --limits=cpu=2` → 파드 생성 실패 이벤트 확인
- 웹 콘솔 **Administration → ResourceQuotas / LimitRanges** 에서도 만들 수 있습니다.

## 채점 / 정리
```bash
lab grade ex280-03
lab finish ex280-03
```
