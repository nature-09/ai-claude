# 사내 메신저 (폐쇄망 OpenShift용)

인터넷이 끊긴 사내망의 OpenShift(OCP)에 올려서 쓰는 웹 메신저입니다.
사용자 1,000~10,000명 규모를 기준으로 만들었고, 백엔드 Pod를 늘려 수평 확장할 수 있습니다.

## 주요 기능

| 구분 | 기능 |
|---|---|
| 채팅 | 1:1 채팅, 그룹 채팅(초대/나가기/이름 변경), 나와의 채팅, 실시간 송수신(WebSocket) |
| 읽음 처리 | 방별 안 읽은 메시지 수, 메시지별 미확인 인원 수 표시, 브라우저 탭 제목에 안 읽은 수 표시 |
| 파일 | 파일·이미지 첨부(버튼/드래그앤드롭/클립보드 붙여넣기), 이미지 미리보기, 위험 확장자 차단 |
| 조직 | 부서 트리 조직도, 사용자 검색, 온라인/오프라인 상태, 프로필(상태 메시지) |
| 알림/검색 | 데스크톱 알림(Notification API), 내가 참여한 대화방 메시지 키워드 검색 |
| 관리 | 사용자 등록·수정·비활성화·비밀번호 초기화, CSV 일괄 등록, 부서 관리 |
| 보안 | BCrypt 비밀번호, JWT 인증, 로그인 5회 실패 시 10분 잠금, 대화방 참여자만 메시지·파일 접근 |
| UI | 한국어, 다크 모드 자동 전환, 모바일 브라우저 대응 |

## 아키텍처

```
                 ┌──────────── OpenShift Route (TLS edge, 타임아웃 1h) ────────────┐
                 │                                                                │
                 ▼                                                                │
   ┌───────────────────────────┐   /api, /ws 프록시   ┌─────────────────────────┐ │
   │ frontend (nginx) x2       │ ───────────────────▶ │ backend (Spring Boot) xN│ │
   │ React 정적 파일           │                      │  REST + STOMP/WebSocket │ │
   └───────────────────────────┘                      └──┬──────────┬───────┬───┘ │
                                                         │          │       │     │
                                          ┌──────────────┘          │       └──────────────┐
                                          ▼                         ▼                      ▼
                                 ┌─────────────────┐     ┌────────────────────┐   ┌─────────────────┐
                                 │ PostgreSQL 16   │     │ Redis 7            │   │ PVC (RWX)       │
                                 │ 사용자/방/메시지│     │ Pod 간 이벤트 중계 │   │ 첨부파일        │
                                 └─────────────────┘     │ 접속상태/로그인잠금│   └─────────────────┘
                                                         └────────────────────┘
```

- **메시지 전송**은 REST(`POST /api/rooms/{id}/messages`)로 저장하고, **실시간 전달**은 WebSocket(STOMP)로 합니다.
- 백엔드 Pod끼리는 **Redis Pub/Sub**로 이벤트를 주고받습니다. 그래서 sticky session 없이 Pod를 늘릴 수 있습니다.
- 브라우저는 nginx 하나만 바라보므로 Route는 1개면 됩니다.

## 디렉터리 구조

```
backend/            Spring Boot 3.5 (Java 21) — REST API, WebSocket, Flyway DB 마이그레이션
frontend/           React 18 + Vite + TypeScript, nginx 설정 포함
helm/messenger/     OCP 배포용 Helm 차트 (PostgreSQL, Redis 포함, 외부 DB/Redis 지정 가능)
openshift/          OCP 내부 빌드용 BuildConfig 템플릿 (사내 Git + Nexus)
scripts/            이미지 빌드, 폐쇄망 반입 번들 생성/업로드 스크립트
docs/DEPLOY.md      폐쇄망 배포 가이드 (상세)
docker-compose.yml  로컬 개발/검증용
```

## 빠른 시작 (로컬 개발)

필요한 것: JDK 21, Maven 3.9+, Node.js 20+, PostgreSQL 14+, Redis 6+

```bash
# 1) DB 준비
createuser messenger -P          # 비밀번호: messenger
createdb messenger -O messenger

# 2) 백엔드 (http://localhost:8080)
cd backend && mvn spring-boot:run

# 3) 프론트엔드 (http://localhost:5173, /api·/ws 는 8080으로 프록시)
cd frontend && npm install && npm run dev
```

초기 관리자 계정은 `admin` / `admin1234!`입니다. **로그인한 뒤 바로 비밀번호를 바꾸세요.**

컨테이너로 한 번에 띄우려면 `docker compose up --build`를 실행하고 http://localhost:8080 으로 접속합니다.

## 폐쇄망 OCP 배포 요약

자세한 절차는 [docs/DEPLOY.md](docs/DEPLOY.md)를 보세요.

**방식 A. 인터넷 환경에서 빌드한 뒤 반입**

```bash
# (인터넷 환경) 이미지 빌드, tar 저장, Helm 차트를 묶어서 번들 생성
podman login registry.redhat.io
./scripts/export-offline-bundle.sh            # → dist/messenger-offline-1.0.0.tar.gz

# (폐쇄망) 사내 레지스트리에 업로드한 뒤 Helm으로 설치
REGISTRY=registry.corp.local:5000 ./import-offline-bundle.sh
helm upgrade --install messenger ./helm-messenger -n messenger \
  --set global.imageRegistry=registry.corp.local:5000 \
  --set route.host=messenger.apps.ocp.corp.local
```

**방식 B. 폐쇄망 안에서 Nexus 미러로 빌드**

```bash
oc process -f openshift/build-template.yaml \
  -p GIT_URL=https://gitlab.corp.local/team/messenger.git \
  -p BASE_REGISTRY=registry.corp.local:5000 \
  -p MAVEN_MIRROR_URL=https://nexus.corp.local/repository/maven-public/ \
  -p NPM_REGISTRY=https://nexus.corp.local/repository/npm-public/ | oc apply -n messenger -f -
oc start-build messenger-backend --follow && oc start-build messenger-frontend --follow
```

## 환경 변수 (백엔드)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `DB_URL` / `DB_USERNAME` / `DB_PASSWORD` | localhost | PostgreSQL 접속 정보 |
| `DB_POOL_SIZE` | 20 | Pod당 DB 커넥션 수 |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` | localhost:6379 | Redis 접속 정보 |
| `JWT_SECRET` | (개발용) | **32바이트 이상 필수**. Helm에서는 자동 생성 |
| `JWT_TTL_HOURS` | 12 | 로그인 유지 시간 |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | admin / admin1234! | 관리자가 한 명도 없을 때만 생성 |
| `FILE_STORAGE_PATH` | ./data/files | 첨부파일 저장 경로 (컨테이너: /data/files) |
| `MAX_FILE_SIZE` | 100MB | 업로드 최대 크기 |
| `FILE_BLOCKED_EXTENSIONS` | exe,bat,... | 업로드를 막을 확장자 |
| `WS_ALLOWED_ORIGINS` | * | WebSocket 허용 Origin (Helm: `https://<route.host>`) |

## API 개요

| 메서드 | 경로 | 설명 |
|---|---|---|
| POST | `/api/auth/login` | 로그인 → JWT |
| GET/PATCH | `/api/users/me` | 내 정보 조회/수정 |
| POST | `/api/users/me/password` | 비밀번호 변경 |
| GET | `/api/users?q=` | 사용자 검색 |
| GET | `/api/departments`, `/api/departments/{id}/users` | 조직도 |
| GET | `/api/presence` | 온라인 사용자 ID 목록 |
| GET | `/api/rooms`, `/api/rooms/{id}` | 대화방 목록/상세 |
| POST | `/api/rooms/direct`, `/api/rooms/group` | 1:1 / 그룹 대화방 생성 |
| POST | `/api/rooms/{id}/members`, `/leave`, `/read` | 초대 / 나가기 / 읽음 처리 |
| GET/POST | `/api/rooms/{id}/messages` | 메시지 조회(커서 페이징)/전송 |
| POST | `/api/rooms/{id}/files` | 파일 전송 (multipart) |
| GET | `/api/files/{id}` | 파일 다운로드 (참여자만) |
| DELETE | `/api/messages/{id}` | 내 메시지 삭제 |
| GET | `/api/messages/search?q=` | 메시지 검색 |
| * | `/api/admin/**` | 사용자/부서 관리 (관리자) |
| WS | `/ws` (STOMP) | CONNECT 헤더 `Authorization: Bearer <JWT>`, 구독: `/user/queue/events`, `/topic/events` |
