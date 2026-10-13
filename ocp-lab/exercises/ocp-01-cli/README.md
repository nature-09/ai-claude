# ocp-01-cli — oc CLI와 웹 콘솔 기본, 프로젝트와 파드

## 목표
- `oc` 로 로그인하고 클러스터 정보를 조회한다
- 프로젝트를 만들고 표시 이름·설명·라벨을 지정한다
- 파드를 실행하고 상태·로그·이벤트를 확인한다
- 웹 콘솔에서 같은 리소스를 찾아본다

## 시작
```bash
lab start ocp-01
eval "$(lab env)"          # LAB_USER, IMG_APP 등 변수 설정
```

## 1. 로그인과 클러스터 둘러보기
```bash
lab login                              # 또는 oc login <API URL> -u ${LAB_USER}
oc whoami
oc whoami --show-server                # API 주소
oc whoami --show-console               # 웹 콘솔 주소
oc get clusterversion                  # 클러스터 버전
oc get nodes -o wide
oc get clusteroperators                # 모든 운영자가 Available=True 인지
oc api-resources | less                # 사용 가능한 리소스 종류
oc explain pod.spec.containers.resources
```

## 2. 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 프로젝트 생성 | 이름 `${LAB_USER}-cli`, 표시 이름 `CLI 실습`, 설명은 자유 |
| 2 | 네임스페이스 라벨 | `env=lab` |
| 3 | 파드 실행 | 이름 `hello`, 이미지 `${IMG_APP}:v1`, 라벨 `tier=frontend` |
| 4 | 노드 목록 저장 | 모든 노드 이름을 `nodes.txt` 파일로 저장하고, 그 파일로 ConfigMap `node-list` 생성 |

<details><summary>힌트</summary>

```bash
oc new-project ${LAB_USER}-cli --display-name="CLI 실습" --description="oc 기본 실습"
oc label namespace ${LAB_USER}-cli env=lab
oc run hello --image=${IMG_APP}:v1 --labels=tier=frontend
cd ${LAB_WORKDIR}/ocp-01-cli
oc get nodes -o name > nodes.txt
oc create configmap node-list --from-file=nodes.txt -n ${LAB_USER}-cli
```
</details>

## 3. 파드 살펴보기
```bash
oc get pods -o wide
oc describe pod hello              # Events 확인 (이미지 pull, 스케줄링)
oc logs hello
oc get pod hello -o yaml | less    # securityContext, openshift.io/scc 어노테이션 확인
oc rsh hello                       # 파드 안으로 접속
  id                               #  → 임의 UID(1000xxxxxx)로 실행됨 (restricted-v2 SCC)
  curl -s localhost:8080/
  exit
oc exec hello -- curl -s localhost:8080/info
oc port-forward pod/hello 18080:8080 &   # 로컬에서 접속 시험
curl -s localhost:18080/ ; kill %1
```

## 4. 웹 콘솔 (4.19+)
- 4.19 부터 Administrator/Developer 화면이 하나로 합쳐졌습니다. 왼쪽 메뉴에서
  **Home → Projects** 로 `${LAB_USER}-cli` 를 찾아 라벨·어노테이션을 확인합니다.
- **Workloads → Pods → hello** 에서 Logs, Terminal, Events 탭을 확인합니다.
- 오른쪽 위 **?** → **Command line tools** 에서 oc 다운로드 위치를 확인합니다 (폐쇄망은 bastion에 이미 설치됨).
- 오른쪽 위 사용자 메뉴 → **Copy login command** 로 토큰 로그인 명령을 얻을 수 있습니다.

## 채점 / 정리
```bash
lab grade ocp-01
lab finish ocp-01
```
