# ocp-06-troubleshoot — 장애 진단

## 목표
상태(Status) → 이벤트(Events) → 로그(Logs) → 설정(YAML) 순서로 원인을 찾아 고칩니다.

## 시작
```bash
lab start ocp-06
eval "$(lab env)"
oc get pods
```

## 과제
`${LAB_USER}-trouble` 프로젝트에 고장 난 앱 5개가 있습니다. 모두 정상화하세요.
(Deployment 를 지우고 새로 만들지 말고 **고쳐서** 살리세요.)

| 앱 | 증상 | 고쳐야 할 상태 |
|---|---|---|
| `app-image` | 파드가 뜨지 않음 | `${IMG_APP}:v1` 이미지로 Ready |
| `app-svc` | 파드는 Running 인데 라우트 접속 시 오류 | Route 로 응답 |
| `app-config` | 컨테이너가 생성되지 않음 | Secret `app-db-secret`(키 `password`, 값 자유) 생성 후 Ready |
| `app-probe` | Running 인데 READY 0/1 | readiness 경로를 앱의 실제 경로로 수정 |
| `app-sched` | Pending | CPU 요청을 100m 로 줄여 Running |

## 진단 명령 모음
```bash
oc get pods                              # STATUS 열: ImagePullBackOff, CreateContainerConfigError, Pending ...
oc describe pod <파드>                    # 맨 아래 Events 가 가장 중요
oc get events --sort-by=.lastTimestamp
oc logs <파드> [--previous]               # 재시작된 컨테이너의 이전 로그
oc get endpoints app-svc                 # 서비스가 파드를 찾았는지 (IP:포트)
oc get svc app-svc -o yaml               # port / targetPort / selector
oc exec deploy/app-svc -- curl -s localhost:8080/   # 파드 안에서 직접 시험
oc debug deploy/app-config               # 같은 스펙의 디버그 파드로 셸 실행
oc adm top pods                          # 리소스 사용량 (metrics 필요)
oc describe node <노드> | grep -A5 Allocated   # 노드 할당 가능 자원
```

<details><summary>힌트</summary>

- app-image: `oc set image deployment/app-image lab-app=${IMG_APP}:v1`
- app-svc: `oc edit svc app-svc` → `targetPort: 8080`
- app-config: `oc create secret generic app-db-secret --from-literal=password=labpass`
- app-probe: 앱은 `/readyz` 를 제공합니다 → `oc set probe deployment/app-probe --readiness --get-url=http://:8080/readyz`
- app-sched: `oc set resources deployment/app-sched --requests=cpu=100m`
</details>

## 채점 / 정리
```bash
lab grade ocp-06
lab finish ocp-06
```
