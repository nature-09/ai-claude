# ex280-11-non-http — HTTP 가 아닌 서비스 노출

## 목표 (EX280: Expose non-HTTP/SNI applications)
Route 는 HTTP/HTTPS(SNI)만 처리합니다. DB, MQ, 사내 TCP 프로토콜처럼 HTTP 가 아닌 서비스는
**NodePort** 나 **LoadBalancer** 서비스로 노출합니다.

`echo` 앱은 TCP 9000 포트에서 접속하면 인사말을 보내고, 받은 줄을 그대로 돌려줍니다.

## 시작
```bash
lab start ex280-11
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-11-non-http        # tcp-test.sh
oc get ipaddresspools -A                    # MetalLB 주소 풀 (강사가 구성)
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | NodePort | Service `echo-nodeport`, 포트 9000 → 9000 |
| 2 | 접속 시험 | `노드 IP:nodePort` 로 bastion 에서 접속 |
| 3 | LoadBalancer | Service `echo-lb`, 포트 9000 → 9000 |
| 4 | 접속 시험 | `EXTERNAL-IP:9000` 으로 접속 (MetalLB 구성 시) |

<details><summary>힌트</summary>

```bash
oc expose deployment echo --name=echo-nodeport --type=NodePort --port=9000 --target-port=9000
oc get svc echo-nodeport                     # PORT(S) 9000:3xxxx/TCP
NODE=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(oc get svc echo-nodeport -o jsonpath='{.spec.ports[0].nodePort}')
./tcp-test.sh $NODE $PORT

oc expose deployment echo --name=echo-lb --type=LoadBalancer --port=9000 --target-port=9000
oc get svc echo-lb -w                        # EXTERNAL-IP 할당 대기
./tcp-test.sh $(oc get svc echo-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}') 9000
```
</details>

## 알아둘 것
- NodePort 범위는 기본 30000–32767 입니다. 방화벽이 bastion → 노드 사이 이 범위를 막고 있으면 2번이 실패합니다.
- 베어메탈/가상화(on-prem) 클러스터에서 LoadBalancer 를 쓰려면 **MetalLB Operator** 와 `IPAddressPool`, `L2Advertisement` 가 필요합니다
  (강사용 `lab-admin metallb <IP 범위>` 참고). 없으면 EXTERNAL-IP 가 계속 `<pending>` 입니다.
- `spec.externalIPs` 로 수동 IP 를 지정하는 방법도 있으나 클러스터 정책(`network.config` 의 `externalIP`)에서 허용해야 합니다.
- 파드 하나만 원격에서 잠깐 접근할 때는 `oc port-forward svc/echo 19000:9000` 도 쓸 수 있습니다.

## 채점 / 정리
```bash
lab grade ex280-11
lab finish ex280-11
```
