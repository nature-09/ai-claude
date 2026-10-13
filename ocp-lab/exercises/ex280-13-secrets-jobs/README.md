# ex280-13-secrets-jobs — Secret, 서비스 어카운트 권한, Job/CronJob

## 목표 (EX280: Configure application security / Manage application workloads)
- 민감 정보를 Secret 으로 만들고 환경 변수로 주입한다
- 서비스 어카운트를 만들고 필요한 역할만 준다
- 서비스 어카운트로 클러스터 API 를 호출하는 CronJob 을 만들고, 수동으로 Job 을 실행한다

## 시작
```bash
lab start ex280-13
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-13-secrets-jobs     # cronjob.yaml 뼈대
oc get pods; oc logs deploy/api             # "필수 환경 변수가 없습니다: API_USER, API_TOKEN"
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | Secret | `api-creds`: `API_USER=labuser`, `API_TOKEN=s3cr3t-token` |
| 2 | 주입 | `api` Deployment 에 Secret 의 모든 키를 환경 변수로 (값을 직접 쓰지 말 것) |
| 3 | 서비스 어카운트 | `report-sa`, 프로젝트 `view` 역할 |
| 4 | CronJob | `report`, 2분마다, `report-sa` 사용, `REPORT_USER` 는 Secret `api-creds` 의 `API_USER` |
| 5 | 수동 실행 | CronJob 으로부터 Job `report-manual` 을 만들어 실행, 로그 확인 |

<details><summary>힌트</summary>

```bash
oc create secret generic api-creds --from-literal=API_USER=labuser --from-literal=API_TOKEN=s3cr3t-token
oc set env deployment/api --from=secret/api-creds
oc create serviceaccount report-sa
oc policy add-role-to-user view -z report-sa
vi cronjob.yaml           # schedule, serviceAccountName, valueFrom.secretKeyRef
oc apply -f cronjob.yaml
oc create job report-manual --from=cronjob/report
oc logs -f job/report-manual
```
`valueFrom` 예시:
```yaml
            - name: REPORT_USER
              valueFrom:
                secretKeyRef:
                  name: api-creds
                  key: API_USER
```
</details>

## 확인
```bash
oc get cronjob,job,pod
oc describe cronjob report
oc get jobs -w                      # 2분마다 Job 생성 (Ctrl+C)
oc auth can-i list pods --as=system:serviceaccount:${LAB_USER}-jobs:report-sa
oc auth can-i delete pods --as=system:serviceaccount:${LAB_USER}-jobs:report-sa
```

## 알아둘 것
- 명령으로 CronJob 을 만들 수도 있습니다:
  `oc create cronjob report --image=${IMG_TOOLBOX} --schedule='*/2 * * * *' -- oc get pods -o name`
  (SA 와 Secret 참조는 이후 `oc edit` / `oc patch` 로 추가)
- 일반 Job: `oc create job once --image=${IMG_UBI} -- date`
- 일시 정지: `oc patch cronjob report -p '{"spec":{"suspend":true}}'`
- 파드 안에서 SA 토큰은 `/var/run/secrets/kubernetes.io/serviceaccount/token` 에 자동 마운트됩니다. oc 는 이 토큰을 자동으로 사용합니다.
- 장기 토큰이 필요한 외부 시스템용: `oc create token report-sa --duration=24h` (단기 토큰 권장)

## 채점 / 정리
```bash
lab grade ex280-13
lab finish ex280-13
```
