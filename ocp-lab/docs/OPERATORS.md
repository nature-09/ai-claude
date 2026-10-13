# 실습용 오퍼레이터 목록과 미러링

폐쇄망 OCP 의 OperatorHub 는 oc-mirror 로 미러링한 카탈로그만 보여 줍니다.
ocp-lab 에 필요한 오퍼레이터는 아래와 같습니다. 미러링 설정 파일: [`mirror/imageset-config.yaml`](../mirror/imageset-config.yaml)

| 오퍼레이터 (패키지) | 구분 | 쓰는 실습 | 설치 방법 | 비고 |
|---|---|---|---|---|
| Red Hat build of Keycloak (`rhbk-operator`) | **필수** | ex280-14 | 수강생이 각자 네임스페이스에 설치 | OwnNamespace/SingleNamespace 지원 → 공유 클러스터에서 수강생별 설치 가능. 실습은 설치·승인·CSV 확인까지만 하므로 DB 불필요 |
| MetalLB (`metallb-operator`) | 권장 | ex280-11 | 강사가 1회 설치 | 없으면 LoadBalancer 과제는 SKIP. L2 모드에 쓸 **노드와 같은 대역의 미사용 IP** 가 필요 |
| Web Terminal (`web-terminal`, `devworkspace-operator`) | 선택 | 전체 | 강사가 1회 설치 (AllNamespaces) | 콘솔 오른쪽 위 `>_` 아이콘으로 브라우저 터미널. bastion 접속이 어려운 수강생용 |
| LVM Storage (`lvms-operator`) | 선택 | ocp-04, ex280-08, ex280-15 | 강사 | 기본 StorageClass 가 없을 때만 |
| Data Grid (`datagrid`) / AMQ Broker (`amq-broker-rhel8`) | 선택 | ex280-14 대체 | — | `LAB_OPERATOR_PACKAGE` 로 바꿔서 사용. OwnNamespace 지원 여부 확인 |

> 이미 클러스터에 같은 카탈로그(예: `cs-redhat-operator-index`)가 있다면 패키지만 추가해서 다시 미러링하면 됩니다.
> oc-mirror v2 는 기존 미러 결과와 차이분만 옮깁니다.

## 미러링 절차 (oc-mirror v2)

```bash
# 1) 인터넷 환경 — 파일로 받기 (registry.redhat.io 인증: ~/.docker/config.json 또는 $XDG_RUNTIME_DIR/containers/auth.json)
oc mirror -c mirror/imageset-config.yaml file:///data/oc-mirror --v2

# 2) /data/oc-mirror 를 폐쇄망으로 반입

# 3) 폐쇄망 — 사내 레지스트리로 올리기
oc mirror -c mirror/imageset-config.yaml --from file:///data/oc-mirror docker://registry.corp.local:5000 --v2

# 4) 클러스터에 적용 (생성된 리소스)
oc apply -f /data/oc-mirror/working-dir/cluster-resources/
oc get catalogsource -n openshift-marketplace
oc get packagemanifests -n openshift-marketplace | grep -E 'rhbk|metallb|web-terminal'
```

기본 온라인 카탈로그가 켜져 있으면 끄세요 (폐쇄망에서는 pull 실패만 반복):
```bash
oc patch operatorhub cluster --type=merge -p '{"spec":{"disableAllDefaultSources":true}}'
```

## MetalLB 설치 (강사, 1회)

```bash
oc create namespace metallb-system
cat <<EOF2 | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata: {name: metallb-operator, namespace: metallb-system}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: {name: metallb-operator-sub, namespace: metallb-system}
spec:
  name: metallb-operator
  channel: stable
  source: <카탈로그 소스 이름>          # oc get catalogsource -n openshift-marketplace
  sourceNamespace: openshift-marketplace
EOF2
oc get csv -n metallb-system -w
lab-admin metallb 192.168.10.200-192.168.10.220      # 노드와 같은 L2 대역의 미사용 IP
```

## Web Terminal 설치 (선택)

```bash
cat <<EOF2 | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: {name: web-terminal, namespace: openshift-operators}
spec:
  name: web-terminal
  channel: fast
  source: <카탈로그 소스 이름>
  sourceNamespace: openshift-marketplace
EOF2
```
웹 터미널의 기본 이미지는 미러된 카탈로그에 포함되어 있어 별도 작업이 필요 없습니다.
웹 터미널에는 `lab` 명령이 없으므로 채점은 bastion(또는 lab-shell)에서 합니다.
