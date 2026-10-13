# ex280-04-project-template — 프로젝트 생성 템플릿

## 목표 (EX280: Enable developer self-service)
새 프로젝트를 만들 때마다 쿼터·LimitRange·NetworkPolicy 가 자동으로 들어가도록 프로젝트 요청 템플릿을 만든다.

> **공유 클러스터**: 템플릿은 `openshift-config` 에 `${LAB_USER}-project-request` 라는 이름으로 각자 만듭니다.
> 클러스터에 실제로 적용하는 단계(`projects.config` 변경)는 모든 사람의 프로젝트 생성에 영향을 주므로 **강사 시연**으로 진행합니다.
> (`LAB_SHARED=false` 인 단독 클러스터에서는 적용까지 채점합니다.)

## 시작
```bash
lab start ex280-04
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-04-project-template
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 기본 템플릿 추출 | `oc adm create-bootstrap-project-template -o yaml > project-template.yaml` |
| 2 | 이름 변경 | `metadata.name: ${LAB_USER}-project-request` |
| 3 | ResourceQuota 추가 | 이름 `${PROJECT_NAME}-quota`, pods=20, requests.cpu=4, requests.memory=8Gi, limits.cpu=8, limits.memory=8Gi |
| 4 | LimitRange 추가 | 이름 `${PROJECT_NAME}-limits`, Container default 500m/512Mi, defaultRequest 100m/128Mi |
| 5 | NetworkPolicy 2개 추가 | 같은 네임스페이스 허용, 라우터(openshift-ingress) 허용 |
| 6 | 등록 | `openshift-config` 네임스페이스에 생성 |
| 7 | (단독/강사) 적용 | `projects.config.openshift.io/cluster` 에 템플릿 지정 후 `${LAB_USER}-tpl-test` 프로젝트로 확인 |

## 풀이 가이드
```bash
oc adm create-bootstrap-project-template -o yaml > project-template.yaml
vi project-template.yaml
```
`objects:` 목록 끝(= `parameters:` 바로 위)에 추가합니다. 들여쓰기에 주의하세요.
```yaml
- apiVersion: v1
  kind: ResourceQuota
  metadata:
    name: ${PROJECT_NAME}-quota
    namespace: ${PROJECT_NAME}
  spec:
    hard:
      pods: "20"
      requests.cpu: "4"
      requests.memory: 8Gi
      limits.cpu: "8"
      limits.memory: 8Gi
- apiVersion: v1
  kind: LimitRange
  metadata:
    name: ${PROJECT_NAME}-limits
    namespace: ${PROJECT_NAME}
  spec:
    limits:
    - type: Container
      default: {cpu: 500m, memory: 512Mi}
      defaultRequest: {cpu: 100m, memory: 128Mi}
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-same-namespace
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    ingress:
    - from:
      - podSelector: {}
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-openshift-ingress
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            policy-group.network.openshift.io/ingress: ""
```
```bash
oc create -f project-template.yaml -n openshift-config
# 검증 (실제 생성 없이 결과만 보기)
oc process ${LAB_USER}-project-request -n openshift-config \
   -p PROJECT_NAME=demo -p PROJECT_ADMIN_USER=$(oc whoami) -p PROJECT_REQUESTING_USER=$(oc whoami) | less
```

### 7. 클러스터 적용 (단독 클러스터 / 강사 시연)
```bash
oc edit project.config.openshift.io/cluster
```
```yaml
spec:
  projectRequestTemplate:
    name: ${LAB_USER}-project-request      # 시험에서는 보통 project-request
```
```bash
oc get pods -n openshift-apiserver -w        # 재시작 완료까지 (1~3분)
oc new-project ${LAB_USER}-tpl-test
oc get resourcequota,limitrange,networkpolicy -n ${LAB_USER}-tpl-test
```
웹 콘솔: **Administration → Cluster Settings → Configuration → Project** 에서도 지정할 수 있습니다.

> 템플릿은 **새로 만드는** 프로젝트에만 적용됩니다. 기존 프로젝트에는 영향이 없습니다.

## 채점 / 정리
```bash
lab grade ex280-04
lab finish ex280-04      # 템플릿 삭제 (단독 모드에서는 projects.config 원복)
```
