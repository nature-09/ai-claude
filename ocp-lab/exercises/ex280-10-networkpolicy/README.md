# ex280-10-networkpolicy — NetworkPolicy 로 파드 간 통신 제어

## 목표 (EX280: Configure network security — network policies)
- 기본 차단(deny-all) 정책을 만든다
- 라우터(openshift-ingress)에서 오는 트래픽을 허용한다
- 파드 라벨·네임스페이스 라벨로 필요한 통신만 허용한다

## 구성
```
 [외부] ──Route──▶ ┌────────── ${LAB_USER}-np-app ──────────┐
                  │  web (app=web) ──8080──▶ db (app=db)  │
 ${LAB_USER}-np-client                                     │
  client ────────▶│  web 만 허용, db 는 차단               │
 (ns 라벨 network=client)                                 │
                  └───────────────────────────────────────┘
```

## 시작
```bash
lab start ex280-10
eval "$(lab env)"
```
### 시험 명령 (정책 적용 전후로 반복 실행)
```bash
A=${LAB_USER}-np-app; C=${LAB_USER}-np-client
t() { printf '%-22s ' "$1"; oc exec -n $2 deploy/$3 -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' $4 || echo 차단됨; }
t "web → db"      $A web   http://db.$A.svc:8080/
t "client → web"  $C client http://web.$A.svc:8080/
t "client → db"   $C client http://db.$A.svc:8080/
t "db → web"      $A db    http://web.$A.svc:8080/
curl -s -m 3 http://$(oc get route web -n $A -o jsonpath='{.spec.host}')/ || echo "route 차단됨"
```

## 과제 (`${LAB_USER}-np-app` 에 생성)

| # | 정책 이름 | 내용 |
|---|---|---|
| 1 | `deny-all` | 모든 파드, Ingress 전부 차단 |
| 2 | `allow-from-ingress` | 라우터 네임스페이스(라벨 `policy-group.network.openshift.io/ingress: ""`)에서 `app=web` 으로 허용 |
| 3 | `allow-web-to-db` | `app=web` 파드 → `app=db` 파드 TCP 8080 허용 |
| 4 | `allow-client-to-web` | 라벨 `network=client` 네임스페이스 → `app=web` TCP 8080 허용 |

최종 결과: route→web ✅, web→db ✅, client→web ✅, client→db ❌, db→web ❌

<details><summary>예시 (deny-all, allow-web-to-db)</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-db
spec:
  podSelector:
    matchLabels: {app: db}
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: web}
    ports:
    - protocol: TCP
      port: 8080
```
</details>

## 알아둘 것
- NetworkPolicy 는 **허용 목록(합집합)** 입니다. 어떤 정책이 파드를 선택하는 순간 그 파드는 "허용된 것만" 받습니다.
- `from` 아래에서 `- namespaceSelector` 와 `podSelector` 를 **한 항목**에 쓰면 AND, **두 항목**으로 쓰면 OR 입니다.
- 네임스페이스 이름으로 고르려면 자동 라벨 `kubernetes.io/metadata.name=<이름>` 을 씁니다.
- 라우터는 hostNetwork 로 동작하는 환경도 있어 `policy-group.network.openshift.io/ingress: ""` 라벨을 쓰는 것이 안전합니다.
- 모니터링을 허용하려면 `network.openshift.io/policy-group: monitoring` 라벨의 네임스페이스를 허용합니다.
- 확인: `oc get networkpolicy`, `oc describe networkpolicy <이름>`, 웹 콘솔 **Networking → NetworkPolicies**

## 채점 / 정리
```bash
lab grade ex280-10
lab finish ex280-10
```
