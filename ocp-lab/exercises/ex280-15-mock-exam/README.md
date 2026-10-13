# ex280-15-mock-exam — EX280 모의고사

- 100점 만점, **70점 이상 합격** (실제 EX280 도 300점 중 210점, 70%)
- 권장 시간 **2시간**. 실제 시험처럼 가이드·힌트 없이 풀어 보세요. 공식 문서(docs.redhat.com)는 실제 시험에서도 볼 수 없으니 `oc explain`, `--help` 를 활용합니다.
- 중간 채점 가능: `lab grade ex280-15` (부분 점수 표시)
- 이름·값은 **문제에 적힌 그대로** 써야 채점됩니다. `<U>` 는 본인 `${LAB_USER}` 입니다.
- 작업 디렉터리 `${LAB_WORKDIR}/ex280-15-mock-exam` 에 사내 CA(`ca.crt`, `ca.key`)와 Helm 차트(`lab-web`)가 있습니다.
- 사용 이미지: `${IMG_APP}:v2`, `${IMG_UBI}`

## 시작
```bash
lab start ex280-15
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-15-mock-exam
```

---

### 문제 1. 인증 (10점)
HTPasswd ID 공급자를 추가하세요.
- IdP 이름 `<U>-exam`, Secret 은 `openshift-config` 의 `<U>-exam-htpasswd`
- 사용자 `<U>-alice` (비밀번호 `alice123`), `<U>-bob` (비밀번호 `bob123`)
- (공유 클러스터) 기존 IdP 를 지우지 마세요.

### 문제 2. 그룹과 권한 (10점)
- 그룹 `<U>-leads` 에 `<U>-alice`, 그룹 `<U>-devs` 에 `<U>-bob`
- `<U>-leads` 는 프로젝트 `<U>-exam-apps` 를 관리(admin)할 수 있어야 합니다
- `<U>-devs` 는 `<U>-exam-apps` 의 리소스를 만들고 수정할 수 있지만 권한은 관리할 수 없어야 합니다

### 문제 3. 쿼터 (10점)
프로젝트 `<U>-exam-apps` 에
- ResourceQuota `exam-quota`: pods 10, requests.cpu 2, requests.memory 2Gi
- LimitRange `exam-limits`: 컨테이너 기본 요청 cpu 100m / memory 128Mi, 기본 제한 cpu 300m / memory 256Mi

### 문제 4. 애플리케이션 (15점)
프로젝트 `<U>-exam-apps` 에 Deployment `shop` 을 만드세요.
- 이미지 `${IMG_APP}:v2`, 레플리카 2, 컨테이너 포트 8080, Service `shop`(8080)
- ConfigMap `shop-config` 의 `APP_MESSAGE=Exam shop` 을 환경 변수로 사용
- readiness: HTTP `/readyz` 8080, liveness: HTTP `/healthz` 8080
- CPU 요청 200m

### 문제 5. 보안 라우트 (10점)
- `shop` 을 호스트 `<U>-shop.<apps 도메인>` 으로 **edge** 라우트 `shop` 으로 노출
- 인증서는 작업 디렉터리의 사내 CA 로 서명한 것을 사용 (SAN 포함)
- `curl --cacert ca.crt https://<U>-shop.<apps 도메인>/` 가 성공해야 합니다

### 문제 6. 자동 확장 (5점)
`shop` 에 HPA: 최소 2, 최대 5, CPU 70%

### 문제 7. 스토리지 (10점)
- PVC `shop-data` (1Gi, RWO, 기본 StorageClass) 를 만들어 `shop` 의 `/data` 에 마운트
- 여러 노드에서 RWO 볼륨 때문에 롤아웃이 멈추지 않도록 하세요

### 문제 8. 레거시 앱 (10점)
프로젝트 `<U>-exam-legacy` 의 `legacy` 앱이 기동하지 않습니다. 원인을 찾아 해결하세요.
- 서비스 어카운트 이름은 `legacy-sa`, 필요한 최소 권한만 부여

### 문제 9. 네트워크 정책 (10점)
프로젝트 `<U>-exam-apps` 에서
- 모든 Ingress 를 기본 차단하는 `deny-all`
- 라우터와 같은 프로젝트 안의 통신은 허용 (정책 이름 자유)
- 다른 프로젝트(예: `<U>-exam-legacy`)의 파드는 `shop` 에 접근할 수 없어야 합니다

### 문제 10. CronJob (5점)
`<U>-exam-apps` 에 CronJob `audit`: 6시간마다 정각(`0 */6 * * *`), 이미지 `${IMG_UBI}`, 명령 `date`

### 문제 11. Helm (5점)
작업 디렉터리의 차트 `lab-web` 으로 `<U>-exam-apps` 에 릴리스 `promo` 설치
- 레플리카 1, `message=Promo`, 라우트는 만들지 않음

---

## 채점 / 정리
```bash
lab grade ex280-15
lab finish ex280-15      # IdP, 사용자, 그룹, 프로젝트 정리
```
모범 답안 확인(강사): `lab solve ex280-15` 후 `lab grade ex280-15`
