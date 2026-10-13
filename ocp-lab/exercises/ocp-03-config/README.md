# ocp-03-config — ConfigMap 과 Secret 으로 설정 주입

## 목표
- ConfigMap/Secret 을 리터럴·파일로 만든다
- 환경 변수(`envFrom`, `valueFrom`)와 볼륨으로 주입한다
- 설정 변경 시 파드가 어떻게 반영되는지 이해한다

## 시작
```bash
lab start ocp-03
eval "$(lab env)"
cd ${LAB_WORKDIR}/ocp-03-config      # app.properties 파일이 있음
```
`app` Deployment, Service, Route 가 미리 만들어져 있습니다.

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | ConfigMap `app-config` | `APP_MESSAGE=Configured by ConfigMap`, `APP_COLOR=blue` |
| 2 | Secret `app-secret` (generic) | `DB_PASSWORD=r3dh4t123` |
| 3 | ConfigMap `app-files` | `app.properties` 파일로 생성 |
| 4 | `app` 에 환경 변수 주입 | app-config, app-secret 의 모든 키 |
| 5 | `app` 에 볼륨 마운트 | app-files → `/etc/app-config` |

<details><summary>힌트</summary>

```bash
oc create configmap app-config --from-literal=APP_MESSAGE="Configured by ConfigMap" --from-literal=APP_COLOR=blue
oc create secret generic app-secret --from-literal=DB_PASSWORD=r3dh4t123
oc create configmap app-files --from-file=app.properties
oc set env deployment/app --from=configmap/app-config
oc set env deployment/app --from=secret/app-secret
oc set volume deployment/app --add --name=app-files --type=configmap \
   --configmap-name=app-files --mount-path=/etc/app-config
```
</details>

## 확인
```bash
HOST=$(oc get route app -o jsonpath='{.spec.host}')
curl -s http://$HOST/            # 메시지가 바뀌었는지
curl -s http://$HOST/env | grep -E 'APP_|DB_'
curl -s http://$HOST/config      # 마운트된 파일 내용
oc get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
oc extract secret/app-secret --to=-          # Secret 내용을 한 번에 보기
oc set env deployment/app --list             # 주입된 변수 목록
```

## 더 해보기
- ConfigMap 값을 바꾼 뒤(`oc edit cm app-config`) 환경 변수는 **파드를 다시 만들어야** 반영됩니다:
  `oc rollout restart deployment/app`
- 볼륨으로 마운트한 파일은 1분 안팎으로 자동 갱신됩니다 (`/config` 다시 호출). 단, `subPath` 마운트는 갱신되지 않습니다.
- 특정 키만 꺼내 쓰기: `oc set env deployment/app --from=configmap/app-config --keys=APP_COLOR`
- Secret 을 파일로 마운트: `oc set volume deployment/app --add --type=secret --secret-name=app-secret --mount-path=/etc/secret`

## 채점 / 정리
```bash
lab grade ocp-03
lab finish ocp-03
```
