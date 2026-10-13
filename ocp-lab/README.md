# ocp-lab — 폐쇄망 OpenShift 실습 환경 (OCP 기본 + EX280/RHCOA 대비)

이미 구성된 **폐쇄망 OCP 4.19+** 위에서 여러 수강생이 함께 실습할 수 있는 실습 키트입니다.
bastion 에 반입할 **번들(이미지 tar + 도구)** 을 만들고, `lab` 명령으로 실습 준비·채점·정리를 자동화합니다.

- **실습 21개**: OCP 기본 6개 + EX280 대비 14개 + 모의고사 1개 (100점, 자동 채점)
- **여러 명 공유**: 수강생 이름 접두어로 네임스페이스·사용자·IdP 를 분리, 강사용 진도 확인/정리 도구
- **폐쇄망 전제**: 모든 이미지를 사내 레지스트리에서 받음, 인터넷·Git·외부 Helm 저장소 불필요
- **두 가지 사용 방식**: bastion 에 직접 설치(`lab`) 또는 툴박스 컨테이너(`lab-shell`)

## 빠른 시작

```bash
# [인터넷 환경]
podman login registry.redhat.io
./scripts/export-bundle.sh                 # → dist/ocp-lab-bundle-1.0.0.tar.gz

# [폐쇄망 bastion]
tar xzf ocp-lab-bundle-1.0.0.tar.gz && cd ocp-lab-bundle-1.0.0
REGISTRY=registry.corp.local:5000 ./import-bundle.sh
sudo ./install-bastion.sh --registry registry.corp.local:5000 --api https://api.ocp.corp.local:6443

# [강사]
lab-admin check
lab-admin students create 20

# [수강생]
lab init student01 && lab login && eval "$(lab env)"
lab list
lab start ex280-05 ; lab guide ex280-05 ; lab grade ex280-05 ; lab finish ex280-05
```
> 사내 메신저(저장소 루트)와는 **별개 프로젝트**입니다. 코드·이미지·번들을 공유하지 않으며 같은 클러스터에 함께 올려도 충돌하지 않습니다.

**적용 절차(체크리스트): [docs/APPLY.md](docs/APPLY.md)** · 상세 설치: [docs/INSTALL.md](docs/INSTALL.md) · 강사용: [docs/INSTRUCTOR.md](docs/INSTRUCTOR.md) · 오퍼레이터 미러링: [docs/OPERATORS.md](docs/OPERATORS.md)

## 실습 목록

### OCP 기본 기능
| ID | 내용 |
|---|---|
| ocp-01-cli | oc CLI·웹 콘솔 기본, 프로젝트, 파드, 라벨 |
| ocp-02-deploy | Deployment·Service·Route, 스케일, 롤링 업데이트, 셀프 힐링 |
| ocp-03-config | ConfigMap·Secret 을 환경 변수/볼륨으로 주입 |
| ocp-04-template-storage | OpenShift Template 으로 MySQL 배포, PVC 데이터 유지 |
| ocp-05-build | ImageStream, S2I 바이너리 빌드(httpd), 이미지 트리거 |
| ocp-06-troubleshoot | 고장 난 앱 5개 진단 (ImagePull, Service, Secret, 프로브, 스케줄링) |

### EX280 (Red Hat Certified OpenShift Administrator) 대비
| ID | 내용 | 클러스터 설정 |
|---|---|---|
| ex280-01-users | HTPasswd IdP, 사용자 추가/비밀번호 변경/삭제, cluster-admin | OAuth (수강생별 IdP) |
| ex280-02-rbac | 그룹, 역할 바인딩, 사용자 정의 Role, SA, self-provisioner | (공유 시 시연) |
| ex280-03-quota-limits | ResourceQuota, LimitRange, ClusterResourceQuota | |
| ex280-04-project-template | 프로젝트 요청 템플릿 (쿼터·LimitRange·NetworkPolicy 자동 생성) | (공유 시 시연) |
| ex280-05-deploy-rollout | 롤링 전략, 롤아웃/롤백, digest 고정, ImageStream 태그 승격 | |
| ex280-06-helm-kustomize | Helm install/upgrade/rollback, Kustomize overlay | |
| ex280-07-reliability | readiness/liveness, requests/limits, HPA | |
| ex280-08-storage | StorageClass, PVC 추가, ConfigMap/emptyDir 볼륨 | |
| ex280-09-routes-tls | edge/passthrough/re-encrypt 라우트, 사내 CA 인증서, 서비스 CA | |
| ex280-10-networkpolicy | deny-all, 라우터 허용, 파드·네임스페이스 셀렉터 | |
| ex280-11-non-http | NodePort, LoadBalancer(MetalLB) 로 TCP 서비스 노출 | |
| ex280-12-scc | SCC 진단, SA + anyuid 로 root 필요 앱 실행 | |
| ex280-13-secrets-jobs | Secret 주입, SA 권한, CronJob/Job | |
| ex280-14-operators | PackageManifest, OperatorGroup/Subscription, InstallPlan 승인 | |
| ex280-15-mock-exam | 모의고사 11문항 100점 (70점 합격) | OAuth |

## lab 명령

| 명령 | 설명 |
|---|---|
| `lab init <이름>` | 수강생 이름(접두어) 설정 |
| `lab login` | `LAB_API_URL` 로 로그인 |
| `lab list` / `lab guide <ID>` | 실습 목록 / 가이드 (Markdown) |
| `lab start <ID>` | 네임스페이스·초기 리소스·작업 파일(`~/ocp-lab-work/<ID>`) 준비 |
| `lab grade <ID>` | 자동 채점 (PASS/FAIL, 모의고사는 점수) |
| `lab finish <ID>` | 정리 (클러스터 설정 원복 포함) |
| `lab solve <ID>` | 모범 답안 적용 (강사 시연, 사전 검증) |
| `lab status` / `lab env` | 내 실습 현황 / 셸 변수 (`eval "$(lab env)"`) |
| `lab-admin check` | 클러스터 사전 점검 (이미지 pull, 스토리지, 메트릭, MetalLB, 카탈로그 ...) |
| `lab-admin students create <N>` | 수강생 계정 일괄 생성 |
| `lab-admin progress <ID\|all>` | 수강생별 채점 현황 |
| `lab-admin cleanup <수강생\|--all>` | 실습 리소스 정리 |
| `lab-shell` | 툴박스 컨테이너 셸 실행 |

## 디렉터리 구조

```
bin/              lab, lab-admin, lab-shell
lib/common.sh     공통 함수 (설정, 네임스페이스, 채점 헬퍼, OAuth, 인증서)
exercises/<ID>/   README.md(가이드), lab.sh(start/grade/finish/solve), files/(작업 파일), manifests/(초기 리소스)
images/lab-app/   실습용 샘플 앱 (Go) — HTTP/HTTPS/TCP echo, 프로브·CPU 부하·파일 저장 엔드포인트
images/toolbox/   툴박스 이미지 (ubi9 + oc/kubectl/helm + lab)
mirror/           oc-mirror ImageSetConfiguration (실습용 오퍼레이터)
scripts/          build-images.sh, export-bundle.sh (인터넷) / import-bundle.sh, install-bastion.sh (bastion)
docs/             APPLY.md(적용 절차), INSTALL.md, INSTRUCTOR.md, OPERATORS.md
lab.env.example   /etc/ocp-lab/lab.env 견본
```

## 실습 앱(lab-app) 엔드포인트

| 경로 | 설명 |
|---|---|
| `/` | `Hello from lab-app (version=v1, pod=...) <APP_MESSAGE>` |
| `/healthz`, `/readyz` | liveness / readiness (`READY_DELAY` 초 동안 readyz 503) |
| `/fail-health`, `/toggle-ready` | liveness 실패 전환 / readiness 토글 |
| `/env`, `/config`, `/info` | 환경 변수 / `CONFIG_DIR` 파일 내용 / 버전·UID·IP(JSON) |
| `/data` | GET 목록·`?file=` 내용, POST `?file=이름` 저장 (`DATA_DIR`) |
| `/cpu?ms=500` | CPU 부하 (HPA) |
| TCP 9000 | echo 서버 (NodePort/LoadBalancer) |
| HTTPS 8443 | `/etc/tls/tls.crt`, `tls.key` 가 있을 때 (passthrough/reencrypt) |

## 새 실습 추가하기
`exercises/<ID>/lab.sh` 에 `EX_TITLE`, `EX_NAMESPACES` 와 `ex_start`, `ex_grade`(필수), `ex_finish`, `ex_solve` 를 정의하고
`README.md` 에 가이드를 씁니다. 채점은 `check "설명" <명령>` 형식이며 `lib/common.sh` 의 헬퍼(`jp_eq`, `deploy_ready`, `route_has`, `can_i` ...)를 씁니다.
