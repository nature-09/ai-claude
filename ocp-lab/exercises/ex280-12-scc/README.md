# ex280-12-scc — SCC 와 서비스 어카운트

## 목표 (EX280: Configure application security — SCC, service accounts, privileged apps)
- 파드가 어떤 SCC(Security Context Constraints)로 실행되는지 확인한다
- root 권한이 필요한 레거시 앱 문제를 진단한다
- 전용 서비스 어카운트에 **필요한 최소한의 SCC(anyuid)** 만 부여해서 실행한다

## 시작
```bash
lab start ex280-12
eval "$(lab env)"
oc get pods            # CrashLoopBackOff
```

## 진단
```bash
oc logs deploy/legacy                      # "root(UID 0)로 실행해야 합니다. 현재 UID=1000xxxxxx"
oc get pod -l app=legacy -o yaml | grep -E 'openshift.io/scc|runAsUser'
#   → restricted-v2 SCC 가 이미지의 USER 0 을 무시하고 프로젝트 범위의 임의 UID 를 지정함
oc get scc                                  # 클러스터의 SCC 목록
oc describe scc restricted-v2
oc describe scc anyuid                      # RunAsUser: RunAsAny
# 이 파드 스펙을 어떤 SCC 가 허용하는지 (SA 기준)
oc get deployment legacy -o yaml | oc adm policy scc-subject-review -f -
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 서비스 어카운트 | `legacy-sa` 생성 |
| 2 | SCC 부여 | `legacy-sa` 에 `anyuid` (privileged 는 주지 말 것) |
| 3 | 적용 | Deployment `legacy` 가 `legacy-sa` 를 사용 |
| 4 | 확인 | 파드가 `anyuid` SCC, UID 0 으로 실행되고 Route 로 응답 |

<details><summary>힌트</summary>

```bash
oc create serviceaccount legacy-sa
oc adm policy add-scc-to-user anyuid -z legacy-sa
oc set serviceaccount deployment/legacy legacy-sa
oc rollout status deployment/legacy
oc get pod -l app=legacy -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
curl -s http://$(oc get route legacy -o jsonpath='{.spec.host}')/info
```
</details>

## 알아둘 것
- `oc adm policy add-scc-to-user <scc> -z <sa>` 는 내부적으로 `system:openshift:scc:<scc>` ClusterRole 을 SA 에 바인딩합니다.
  확인: `oc get rolebinding -o wide | grep scc`, `oc auth can-i use scc/anyuid --as=system:serviceaccount:<ns>:legacy-sa`
- 사용자(User)에게 SCC 를 주는 것이 아니라 **파드를 실행하는 SA** 에 줘야 합니다.
- 더 나은 해결책은 이미지를 고쳐 비 root·8080 포트로 실행하는 것입니다. 시험에서는 "주어진 이미지를 그대로 실행" 하도록 요구합니다.
- 파드 보안 승인(Pod Security Admission) 라벨은 OpenShift 가 SA 의 SCC 권한에 맞춰 자동 조정합니다 (`oc get ns ${LAB_USER}-scc --show-labels`).
- 제거: `oc adm policy remove-scc-from-user anyuid -z legacy-sa`

## 채점 / 정리
```bash
lab grade ex280-12
lab finish ex280-12
```
