# ex280-14-operators — OperatorHub/OLM 으로 오퍼레이터 설치

## 목표 (EX280: Manage OpenShift operators)
- 카탈로그(CatalogSource)와 PackageManifest 로 설치할 수 있는 오퍼레이터를 찾는다
- OperatorGroup, Subscription 을 직접 만들어 **CLI 로** 설치한다
- 수동 승인(Manual) InstallPlan 을 승인한다
- 설치 상태(CSV)를 확인하고 제거한다

> 폐쇄망에서는 OperatorHub 가 인터넷 카탈로그 대신 **미러링된 카탈로그**(oc-mirror 로 만든 CatalogSource)를 씁니다.
> 공유 클러스터이므로 각자 자기 네임스페이스에만 설치(OwnNamespace)합니다.
> 기본 실습 오퍼레이터: `rhbk-operator` (Red Hat build of Keycloak) — 강사가 `LAB_OPERATOR_PACKAGE` 로 바꿀 수 있습니다.

## 시작
```bash
lab start ex280-14          # 카탈로그, 기본 채널을 알려 줌
eval "$(lab env)"
```

## 1. 카탈로그 살펴보기
```bash
oc get catalogsource -n openshift-marketplace
oc get packagemanifests -n openshift-marketplace
PKG=rhbk-operator           # lab start 가 알려 준 이름
oc describe packagemanifest $PKG -n openshift-marketplace | less
oc get packagemanifest $PKG -n openshift-marketplace \
  -o jsonpath='{.status.catalogSource}{"\n"}{.status.defaultChannel}{"\n"}{range .status.channels[*]}{.name}{" "}{.currentCSV}{"\n"}{end}'
# 지원 설치 모드 (OwnNamespace / SingleNamespace / MultiNamespace / AllNamespaces)
oc get packagemanifest $PKG -n openshift-marketplace \
  -o jsonpath='{range .status.channels[0].currentCSVDesc.installModes[*]}{.type}={.supported}{"\n"}{end}'
```

## 2. 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | OperatorGroup | `${LAB_USER}-operator` 네임스페이스만 대상 (`targetNamespaces`) |
| 2 | Subscription | 이름 = 패키지 이름, 기본 채널, 카탈로그 소스, `installPlanApproval: Manual` |
| 3 | 승인 | 생성된 InstallPlan 승인 |
| 4 | 확인 | CSV `Succeeded`, 오퍼레이터 파드 Running |

```yaml
# operator.yaml  (<...> 부분을 채우세요)
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${LAB_USER}-operator-og
  namespace: ${LAB_USER}-operator
spec:
  targetNamespaces:
  - ${LAB_USER}-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: <패키지 이름>
  namespace: ${LAB_USER}-operator
spec:
  name: <패키지 이름>
  channel: <채널>
  source: <catalogSource>
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
```
```bash
oc apply -f operator.yaml
oc get subscription,installplan -n ${LAB_USER}-operator
oc patch installplan <install-xxxxx> -n ${LAB_USER}-operator --type=merge -p '{"spec":{"approved":true}}'
oc get csv -n ${LAB_USER}-operator -w            # Succeeded 까지 (Ctrl+C)
oc get pods -n ${LAB_USER}-operator
oc get crd | grep -i keycloak                    # 오퍼레이터가 추가한 API
oc explain keycloak.spec | head -30
```

## 3. 웹 콘솔로 설치하는 방법 (시험에서 자주 사용)
**Operators → OperatorHub** → 오퍼레이터 선택 → **Install** →
Installation mode(특정 네임스페이스), Update approval(Automatic/Manual) 선택 →
**Operators → Installed Operators** 에서 상태 확인, Manual 이면 **Upgrade available / Approve** 클릭.

## 4. 제거 순서
```bash
oc delete subscription <패키지> -n ${LAB_USER}-operator
oc delete csv <CSV 이름> -n ${LAB_USER}-operator
# (클러스터에서 완전히 지울 때만) CRD 삭제 — 공유 클러스터에서는 하지 마세요
```

## 알아둘 것
- 클러스터 전체 오퍼레이터(AllNamespaces)는 보통 `openshift-operators` 네임스페이스(기본 OperatorGroup 존재)에 설치합니다.
- `installPlanApproval: Automatic` 이면 새 버전이 카탈로그에 들어올 때 자동 업그레이드됩니다. 운영 환경은 Manual 권장.
- 특정 버전으로 고정하려면 `startingCSV` 를 지정합니다.

## 채점 / 정리
```bash
lab grade ex280-14
lab finish ex280-14
```
