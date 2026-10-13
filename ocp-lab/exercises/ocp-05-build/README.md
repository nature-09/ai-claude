# ocp-05-build — 이미지 스트림과 S2I 바이너리 빌드

폐쇄망에서는 Git 저장소나 인터넷 의존성 없이 **로컬 디렉터리를 업로드해 빌드하는 바이너리 빌드**를 자주 씁니다.
여기서는 사내 레지스트리에 반입된 `httpd-24` S2I 빌더 이미지로 정적 웹사이트 이미지를 만듭니다.

## 목표
- 외부(사내) 레지스트리 이미지를 ImageStream 으로 가져온다
- BuildConfig(Source 전략, Binary 입력)를 만들고 빌드를 실행한다
- 빌드 결과(ImageStreamTag)가 바뀌면 Deployment 가 자동으로 갱신되는 것을 확인한다

## 사전 조건
내부 이미지 레지스트리(image-registry)가 Managed 상태여야 합니다 (`oc get configs.imageregistry cluster -o jsonpath='{.spec.managementState}'`).

## 시작
```bash
lab start ocp-05
eval "$(lab env)"
cd ${LAB_WORKDIR}/ocp-05-build      # html/index.html
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | ImageStream | `httpd-24:latest` ← `${IMG_HTTPD}` |
| 2 | BuildConfig | 이름 `web`, 빌더 `httpd-24:latest`, 바이너리 입력 |
| 3 | 첫 빌드 | `html/` 디렉터리로 빌드 |
| 4 | 배포/노출 | ImageStream `web:latest` 로 Deployment `web`, Route `web` |
| 5 | 두 번째 빌드 | `index.html` 의 `version 1` → `version 2` 로 바꾸고 다시 빌드 → 자동 재배포 |

<details><summary>힌트</summary>

```bash
oc import-image httpd-24:latest --from=${IMG_HTTPD} --confirm
oc new-build --name=web --binary --image-stream=httpd-24:latest
oc start-build web --from-dir=html --follow
oc new-app --image-stream=web:latest --name=web      # 트리거 어노테이션 자동 설정
oc expose service web --port=8080            # httpd 서비스는 8080/8443 두 포트
sed -i 's/version 1/version 2/' html/index.html
oc start-build web --from-dir=html --follow
```
</details>

## 확인
```bash
oc get is,istag
oc describe is web                     # 빌드할 때마다 새 이미지 digest 가 쌓임
oc get bc,build
oc logs -f bc/web                      # 최근 빌드 로그
oc get deployment web -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}{"\n"}'
oc rollout history deployment/web
curl -s http://$(oc get route web -o jsonpath='{.spec.host}')/
```

## 더 해보기
- Docker 전략 빌드: `Containerfile` 을 만들고 `oc new-build --name=web2 --binary --strategy=docker` 후
  `oc start-build web2 --from-dir=.`  (`FROM ${IMG_HTTPD}` 처럼 사내 레지스트리 이미지를 써야 함)
- `oc set triggers deployment/web` 로 트리거 목록 확인, `--manual` 로 자동 배포 끄기
- 폐쇄망에서 Git 소스 빌드를 하려면 사내 Git(GitLab 등) + Maven/npm 미러(Nexus)가 필요합니다

## 채점 / 정리
```bash
lab grade ocp-05
lab finish ocp-05
```
