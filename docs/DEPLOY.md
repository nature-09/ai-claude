# 폐쇄망 OpenShift 배포 가이드

## 0. 사전 준비 사항

| 항목 | 내용 |
|---|---|
| OpenShift | 4.12 이상 (Kubernetes 1.25+), 기본 `restricted-v2` SCC로 실행됩니다 (추가 권한 필요 없음) |
| 사내 이미지 레지스트리 | Quay, Harbor, Nexus Docker 등. OCP 내부 레지스트리도 사용할 수 있습니다 |
| 스토리지 | DB용 RWO StorageClass, 첨부파일용 **RWX** StorageClass (ODF CephFS, NFS 등) |
| 도구 | `oc`, `helm` 3.x, `podman`(또는 docker) |
| 도메인/인증서 | Route 호스트 (예: `messenger.apps.ocp.corp.local`). 사내 인증서가 있으면 `route.tls.*`에 지정합니다 |

> **데스크톱 알림**과 **클립보드 이미지 붙여넣기**는 브라우저 정책상 HTTPS에서만 동작합니다. Route TLS를 꼭 켜세요(기본값).

## 1. 이미지 준비

### 방식 A — 인터넷 환경에서 빌드한 뒤 반입 (권장)

인터넷 환경 PC에서 다음을 실행합니다.

```bash
git clone <이 저장소> && cd messenger
podman login registry.redhat.io                 # PostgreSQL/Redis RHEL 이미지 pull 용
./scripts/export-offline-bundle.sh              # VERSION 파일 기준 버전
# → dist/messenger-offline-1.0.0.tar.gz (이미지 4종 + Helm 차트 + 업로드 스크립트)
```

번들에는 다음이 들어 있습니다.

```
images/messenger-backend.tar   images/messenger-frontend.tar
images/postgresql.tar          images/redis.tar
images/images.txt              images/SHA256SUMS
helm-messenger/                import-offline-bundle.sh   DEPLOY.md
```

보안 절차에 따라 번들을 폐쇄망으로 반입한 뒤, 폐쇄망에서 다음을 실행합니다.

```bash
tar xzf messenger-offline-1.0.0.tar.gz && cd messenger-offline-1.0.0
podman login registry.corp.local:5000
REGISTRY=registry.corp.local:5000 ./import-offline-bundle.sh
# 사설 인증서 레지스트리면 TLS_VERIFY=false 를 추가합니다
```

**OCP 내부 레지스트리를 쓰는 경우**

```bash
oc new-project messenger
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}'  # 관리자, 1회
HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
podman login -u $(oc whoami) -p $(oc whoami -t) $HOST
# 이미지 경로는 <레지스트리>/<네임스페이스>/<이미지> 이므로 네임스페이스 'messenger' 와 맞춰집니다
REGISTRY=$HOST TLS_VERIFY=false ./import-offline-bundle.sh
# 단, rhel9/postgresql-16, rhel9/redis-7 이미지는 'rhel9' 프로젝트가 필요합니다: oc new-project rhel9
# 또는 Helm 값에서 postgresql.image.repository=messenger/postgresql-16 처럼 바꿔서 push 합니다
```

설치할 때는 클러스터 내부 주소를 사용합니다:
`--set global.imageRegistry=image-registry.openshift-image-registry.svc:5000`

### 방식 B — 폐쇄망 안에서 빌드 (Nexus 미러 사용)

필요한 것:
- 사내 Git(GitLab 등)에 이 저장소가 올라가 있어야 합니다.
- Nexus의 Maven proxy(`maven-public`)와 npm proxy(`npm-public`)에 의존성이 캐시되어 있거나 접근 가능해야 합니다.
- 사내 레지스트리에 `ubi9/openjdk-21`, `ubi9/openjdk-21-runtime`, `ubi9/nodejs-22`, `ubi9/nginx-124`가 미러링되어 있어야 합니다.

```bash
oc new-project messenger
oc process -f openshift/build-template.yaml \
  -p GIT_URL=https://gitlab.corp.local/team/messenger.git \
  -p GIT_REF=main \
  -p VERSION=1.0.0 \
  -p BASE_REGISTRY=registry.corp.local:5000 \
  -p MAVEN_MIRROR_URL=https://nexus.corp.local/repository/maven-public/ \
  -p NPM_REGISTRY=https://nexus.corp.local/repository/npm-public/ \
  | oc apply -f -

# Git 인증이 필요한 경우
oc create secret generic git-cred --type=kubernetes.io/basic-auth \
  --from-literal=username=<id> --from-literal=password=<token>
oc set build-secret --source bc/messenger-backend git-cred
oc set build-secret --source bc/messenger-frontend git-cred

oc start-build messenger-backend --follow
oc start-build messenger-frontend --follow
```

사내 Git이 없으면 로컬 디렉터리를 바이너리 빌드로 올릴 수 있습니다.

```bash
oc start-build messenger-backend --from-dir=backend --follow
oc start-build messenger-frontend --from-dir=frontend --follow
```

이 경우 BuildConfig의 `source`를 `type: Binary`로 바꾸거나, `oc new-build --binary --strategy=docker --name=messenger-backend`로 BuildConfig를 따로 만듭니다.

OCP 밖의 빌드 서버에서 빌드할 때는 `scripts/build-images.sh`에 `BASE_REGISTRY`, `MAVEN_MIRROR_URL`, `NPM_REGISTRY` 환경 변수를 지정해 실행합니다.

> Nexus가 사설 인증서를 쓰면 빌더 이미지에 사내 CA를 넣거나, OCP의 `additionalTrustedCA`(빌드 클러스터 설정)에 CA를 등록하세요.

## 2. Helm 설치

`values-prod.yaml`을 작성합니다.

```yaml
global:
  imageRegistry: registry.corp.local:5000
  # imagePullSecrets:
  #   - name: corp-registry-pull

route:
  host: messenger.apps.ocp.corp.local
  # 사내 인증서 사용 시
  # tls:
  #   certificate: |
  #     -----BEGIN CERTIFICATE-----
  #   key: |
  #     -----BEGIN PRIVATE KEY-----

app:
  adminPassword: "초기관리자비밀번호!"   # 비워두면 랜덤 생성

files:
  persistence:
    storageClass: ocs-storagecluster-cephfs   # RWX 가능한 StorageClass
    size: 500Gi

postgresql:
  persistence:
    storageClass: ocs-storagecluster-ceph-rbd
    size: 100Gi
```

설치합니다.

```bash
helm upgrade --install messenger ./helm-messenger -n messenger -f values-prod.yaml
oc get pods -n messenger -w
```

설치가 끝나면 NOTES 안내대로 관리자 비밀번호를 확인합니다.

```bash
oc get secret messenger-secret -n messenger -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d
```

### 레지스트리 pull secret이 필요한 경우

```bash
oc create secret docker-registry corp-registry-pull -n messenger \
  --docker-server=registry.corp.local:5000 --docker-username=<id> --docker-password=<pw>
# values: global.imagePullSecrets: [{name: corp-registry-pull}]
```

### 외부(기존) DB/Redis를 쓰는 경우

```yaml
postgresql:
  enabled: false
externalDatabase:
  url: jdbc:postgresql://pg.corp.local:5432/messenger
  username: messenger
  existingSecret: messenger-db      # DB_PASSWORD 키를 가진 Secret
redis:
  enabled: false
externalRedis:
  host: redis.corp.local
  port: 6379
  password: "..."
```

외부 PostgreSQL에서는 `pg_trgm` 확장을 쓸 수 있어야 합니다. 앱 계정이 DB 소유자이면 Flyway가 자동으로 생성합니다(PG13 이상). 그렇지 않으면 DBA가 `CREATE EXTENSION pg_trgm;`을 먼저 실행해 주세요.

## 3. 초기 설정

1. `https://<route.host>`에 `admin` 계정으로 로그인합니다. **[내 정보]에서 비밀번호를 바꿉니다.**
2. ⚙️ **관리자 → 부서 관리**에서 부서 트리를 만듭니다. CSV로 일괄 등록하면 부서가 자동으로 생성되므로 이 단계는 건너뛰어도 됩니다.
3. **사용자 관리 → CSV 일괄 등록**으로 직원을 등록합니다.

```csv
username,name,password,department,position,email,phone
hong,홍길동,Init1234!,개발팀,대리,hong@corp.local,010-0000-0000
```

- 파일 인코딩은 UTF-8입니다. 엑셀에서는 "CSV UTF-8"로 저장하세요.
- 이미 있는 아이디는 건너뜁니다.

## 4. 규모별 권장 설정 (1,000 ~ 10,000명)

| 항목 | ~3,000명 | ~10,000명 |
|---|---|---|
| backend replicas (HPA min/max) | 2 / 4 | 3 / 8 |
| backend 리소스 | 0.5~2 CPU, 1~2Gi | 1~2 CPU, 2Gi |
| PostgreSQL | 1~2 CPU, 2Gi, `maxConnections: 200` | 2~4 CPU, 4~8Gi, `maxConnections: 300` |
| `backend.dbPoolSize` | 20 | 20 (max Pod × pool ≤ maxConnections − 여유) |
| frontend replicas | 2 | 2~3 |

- WebSocket은 Pod마다 수천 개의 연결을 처리할 수 있습니다. HPA가 줄어들 때 연결이 끊기지 않도록 축소는 천천히 하게 설정했습니다(10분 안정화).
- 연결이 끊긴 클라이언트는 3초 뒤 자동으로 다시 연결하고, 그 사이 놓친 메시지는 다시 불러옵니다.

## 5. 운영

| 작업 | 명령/방법 |
|---|---|
| 상태 확인 | `oc get pods -l app.kubernetes.io/instance=messenger` |
| 로그 | `oc logs deploy/messenger-backend -f` |
| 헬스체크 | `/actuator/health/liveness`, `/actuator/health/readiness` (클러스터 내부) |
| 메트릭 | `/actuator/prometheus` — `serviceMonitor.enabled=true` (사용자 워크로드 모니터링) |
| 업그레이드 | 새 번들 반입 → 이미지 push → `helm upgrade ... --set backend.image.tag=1.0.1 --set frontend.image.tag=1.0.1` |
| DB 스키마 | 백엔드 기동 시 Flyway가 자동으로 마이그레이션합니다 (여러 Pod가 동시에 떠도 잠금으로 안전) |
| DB 백업 | `oc exec sts/messenger-postgresql -- pg_dump -U messenger messenger > backup.sql` (CronJob으로 정기 실행 권장) |
| 첨부파일 백업 | `messenger-files` PVC 스냅샷 또는 OADP |
| 계정 잠금 해제 | 로그인 5회 실패 시 10분 잠금. 바로 풀려면 `oc exec deploy/messenger-redis -- redis-cli -a $PW DEL login:fail:<아이디>` |

> `helm uninstall`을 해도 Secret과 첨부파일 PVC는 남아 있습니다(`helm.sh/resource-policy: keep`). 완전히 지우려면 따로 삭제하세요.

## 6. 문제 해결

| 증상 | 원인/조치 |
|---|---|
| 화면 왼쪽 아래 연결 표시가 빨간색 | WebSocket 연결 실패. Route 타임아웃 어노테이션과 프록시/방화벽의 WebSocket 허용 여부를 확인하세요 |
| 백엔드 Pod가 `JWT_SECRET ... 32바이트` 오류로 종료 | `app.jwtSecret`을 32자 이상으로 지정하거나 비워 두세요(자동 생성) |
| 첨부파일이 가끔 404 | 백엔드 여러 Pod가 RWO PVC를 쓰고 있습니다. RWX StorageClass로 바꾸세요 |
| `pg_trgm` 생성 실패 | 외부 DB 권한 부족. DBA에게 `CREATE EXTENSION pg_trgm` 실행을 요청하세요 |
| 이미지 pull 실패 | `global.imageRegistry`, pull secret, 이미지 경로(`<registry>/messenger/messenger-backend:<tag>`)를 확인하세요 |
| 데스크톱 알림이 오지 않음 | HTTPS 접속인지, 브라우저 사이트 설정에서 알림이 허용되어 있는지 확인하세요 |
