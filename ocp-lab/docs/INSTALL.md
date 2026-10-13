# 설치 가이드 (인터넷 환경 → 폐쇄망 bastion → OCP)

```
 [인터넷 PC/빌드 서버]                       [폐쇄망 bastion]                         [OCP 4.19+]
  scripts/export-bundle.sh   ── 반입 ──▶  import-bundle.sh  ── push ──▶  사내 레지스트리 ◀── pull ── 실습 파드
  (이미지 빌드 + tar 저장)    (USB 등)    install-bastion.sh                     │
                                          lab / lab-admin / lab-shell ── oc ─────▶ API
```

## 0. 준비물

| 위치 | 필요한 것 |
|---|---|
| 인터넷 환경 | podman(또는 docker), curl, `podman login registry.redhat.io` (MySQL 이미지용 Red Hat 계정) |
| bastion | RHEL 8/9, podman 또는 skopeo, jq, openssl, curl, httpd-tools(htpasswd) — 없으면 사내 RHEL 미러로 설치 |
| 사내 레지스트리 | 클러스터 미러 레지스트리(Quay mirror-registry, Harbor, Nexus 등). 경로 `ocp-lab/` (조직/프로젝트) 생성 |
| OCP | 4.19 이상, cluster-admin, 기본 StorageClass, 내부 이미지 레지스트리 Managed(ocp-05), 메트릭(HPA) |

> **레지스트리 경로**: 모든 실습 이미지는 `<레지스트리>/ocp-lab/<이름>:<태그>` 로 올라갑니다.
> Quay 계열은 `ocp-lab` 조직을 먼저 만들고, 저장소를 **public** 으로 두는 것이 가장 간단합니다
> (private 이면 글로벌 pull secret 에 인증 정보가 있어야 하고, ImageStream import 에도 인증이 필요합니다).

## 1. 인터넷 환경 — 번들 만들기

```bash
git clone <이 저장소> && cd ai-claude/ocp-lab
podman login registry.redhat.io
OC_CHANNEL=stable-4.19 ./scripts/export-bundle.sh       # 클러스터 버전에 맞게 (stable-4.20 등)
# → dist/ocp-lab-bundle-1.0.0.tar.gz (+ .sha256), 약 1.5~2GB
```

번들에 들어가는 이미지

| 레지스트리 경로 | 원본 | 용도 |
|---|---|---|
| `ocp-lab/lab-app:v1`, `:v2` | 직접 빌드 (Go, ubi9-minimal) | 대부분의 실습 앱 |
| `ocp-lab/lab-app:v3` | 직접 빌드 | 기동 실패 버전 (롤백 실습) |
| `ocp-lab/lab-app:legacy` | 직접 빌드 | root 필요 앱 (SCC 실습) |
| `ocp-lab/lab-toolbox:<버전>` | 직접 빌드 (ubi9 + oc/helm/lab) | 툴박스 셸, CronJob 실습 |
| `ocp-lab/ubi9-ubi:latest` | registry.access.redhat.com/ubi9/ubi | Job/CronJob |
| `ocp-lab/ubi9-httpd-24:latest` | registry.access.redhat.com/ubi9/httpd-24 | S2I 빌더 (ocp-05) |
| `ocp-lab/rhel9-mysql-80:latest` | registry.redhat.io/rhel9/mysql-80 | 템플릿/PVC 실습 (ocp-04) |

## 2. bastion — 이미지 업로드

```bash
sha256sum -c ocp-lab-bundle-1.0.0.tar.gz.sha256
tar xzf ocp-lab-bundle-1.0.0.tar.gz && cd ocp-lab-bundle-1.0.0
podman login registry.corp.local:5000
REGISTRY=registry.corp.local:5000 ./import-bundle.sh
#   사설 인증서를 bastion 이 아직 신뢰하지 않으면: TLS_VERIFY=false
```

## 3. bastion — lab 도구 설치

```bash
sudo ./install-bastion.sh --registry registry.corp.local:5000 \
     --api https://api.ocp.corp.local:6443 --shared true
cat /etc/ocp-lab/lab.env
```
- `/opt/ocp-lab` 에 설치되고 `lab`, `lab-admin`, `lab-shell` 명령이 생깁니다.
- bastion 에 oc/helm 이 없으면 번들의 클라이언트를 `/usr/local/bin` 에 설치합니다 (`--force-clients` 로 교체).
- 툴박스 컨테이너만 쓰려면 `--toolbox-only`.

## 4. 클러스터 점검과 수강생 계정 (강사)

```bash
oc login -u kubeadmin https://api.ocp.corp.local:6443
lab-admin check                       # FAIL 항목부터 해결
lab-admin students create 20          # student01~20, 무작위 비밀번호 → ./ocp-lab-students.csv
#   같은 비밀번호로: lab-admin students create 20 student Passw0rd
```
수강생 그룹(`ocp-lab-students`)은 기본으로 **cluster-admin** 을 받습니다. EX280 범위(OAuth, SCC, 쿼터, 오퍼레이터)를 실습하려면 필요합니다.
권한을 줄이려면 `LAB_STUDENT_ROLE=admin lab-admin students create 20` 처럼 지정할 수 있지만 EX280 실습 대부분이 동작하지 않습니다.

선택 구성: MetalLB(ex280-11), Web Terminal — [OPERATORS.md](OPERATORS.md)

## 5. 수강생 사용 방법

### A. bastion 호스트에서 직접
```bash
ssh student01@bastion
lab init student01            # 이름 = 네임스페이스/사용자 접두어 (한 번만)
lab login                     # LAB_API_URL 로 student01 로그인
eval "$(lab env)"             # IMG_APP 등 가이드에서 쓰는 변수
lab list
lab start ocp-01 && lab guide ocp-01
```

### B. 툴박스 컨테이너 (bastion 에 도구를 설치하기 어렵거나 환경을 통일하고 싶을 때)
```bash
lab-shell                     # 사내 레지스트리에서 lab-toolbox 이미지를 받아 실행 (rootless podman)
# 컨테이너 안에서
lab init student01 && lab login && lab list
```
- 작업 파일과 kubeconfig 는 호스트의 `~/ocp-lab-home` 에 저장됩니다.
- 여러 수강생이 bastion 계정 하나를 같이 쓴다면 `LAB_SHELL_HOME=~/ocp-lab-home-student01 lab-shell` 처럼 디렉터리를 나누세요.
- podman 이 사내 레지스트리 CA 를 신뢰하지 않으면 `/etc/containers/certs.d/<레지스트리>/ca.crt` 에 넣거나 lab.env 에 `LAB_TLS_VERIFY=false`.

### C. 직접 실행
```bash
podman run -it --rm --network host -v ~/ocp-lab-home:/work:Z \
  -e LAB_REGISTRY=registry.corp.local:5000 -e LAB_API_URL=https://api.ocp.corp.local:6443 \
  registry.corp.local:5000/ocp-lab/lab-toolbox:1.0.0
```

## 6. 업그레이드
새 번들로 2~3단계를 다시 실행합니다. `/etc/ocp-lab/lab.env` 는 유지됩니다.

## 문제 해결

| 증상 | 확인 |
|---|---|
| 파드가 `ImagePullBackOff` | `lab-admin check` 의 pull 시험, 레지스트리 경로/공개 여부, 노드의 레지스트리 CA 신뢰 |
| `oc import-image` 실패 (ocp-05, ex280-05) | `oc get image.config cluster -o yaml` 의 `additionalTrustedCA` 에 레지스트리 CA, 레지스트리 인증 |
| `lab login` 인증서 오류 | lab.env 에 `LAB_INSECURE_TLS=true` 또는 `LAB_API_CA` 지정 |
| 라우트 호스트에 접속 불가 | bastion 의 DNS 가 `*.apps.<클러스터>` 를 풀어야 함 (`dig x.apps...`) |
| PVC `Pending` | 기본 StorageClass, `WaitForFirstConsumer` 면 파드가 떠야 Bound |
| HPA `TARGETS <unknown>` | requests.cpu 지정 여부, `oc get apiservice v1beta1.metrics.k8s.io` |
| 빌드 실패 (ocp-05) | 내부 이미지 레지스트리 Managed + 스토리지 구성 |
