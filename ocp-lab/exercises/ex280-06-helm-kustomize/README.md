# ex280-06-helm-kustomize — Helm 차트와 Kustomize 로 배포

## 목표 (EX280: Deploy applications — Helm, Kustomize)
- Helm 차트의 values 를 확인하고 설치/업그레이드/롤백한다
- Kustomize base/overlay 구조로 환경별 설정을 만든다

## 시작
```bash
lab start ex280-06
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-06-helm-kustomize
ls lab-web kustomize
```

## Part 1. Helm (`${LAB_USER}-helm`)

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 설치 | 릴리스 `web`, 차트 `./lab-web`, `replicaCount=2`, `message="Installed by Helm"` |
| 2 | 업그레이드 | 기존 값 유지하고 `image.tag=v2` |
| 3 | 롤백 | 리비전 1 로 롤백 (최종 이미지 v1, 리비전 3) |

```bash
helm show chart ./lab-web
helm show values ./lab-web
helm template web ./lab-web --set replicaCount=2 | less     # 설치 전 결과 미리 보기

helm install web ./lab-web -n ${LAB_USER}-helm --set replicaCount=2 --set message="Installed by Helm"
#   values 파일을 쓰려면: helm install web ./lab-web -f my-values.yaml
helm list -n ${LAB_USER}-helm
helm get values web -n ${LAB_USER}-helm

helm upgrade web ./lab-web -n ${LAB_USER}-helm --reuse-values --set image.tag=v2
helm history web -n ${LAB_USER}-helm
helm rollback web 1 -n ${LAB_USER}-helm
helm history web -n ${LAB_USER}-helm
```

> **폐쇄망의 Helm 저장소**: 인터넷 차트 저장소는 쓸 수 없으므로 사내 Nexus/Harbor 차트 저장소를 등록합니다.
> `helm repo add corp https://nexus.corp.local/repository/helm/` → `helm search repo corp` → `helm install web corp/lab-web`.
> OCP 웹 콘솔의 Helm 메뉴에 사내 저장소를 보이게 하려면 `HelmChartRepository` 리소스를 만듭니다.
> 패키징: `helm package ./lab-web` → `lab-web-1.0.0.tgz`

## Part 2. Kustomize

| # | 할 일 | 조건 |
|---|---|---|
| 4 | dev 적용 | `kustomize/overlays/dev` 를 그대로 적용 → `${LAB_USER}-kustomize-dev` |
| 5 | prod 완성 | `overlays/prod/kustomization.yaml` 의 TODO 완성: 네임스페이스 `${LAB_USER}-kustomize-prod`, replicas 3, 이미지 v2, `APP_MESSAGE=prod` |
| 6 | prod 적용 | `oc apply -k` |

```bash
tree kustomize   # 또는 find kustomize
oc kustomize kustomize/overlays/dev             # 결과 YAML 미리 보기
oc apply -k kustomize/overlays/dev
vi kustomize/overlays/prod/kustomization.yaml
oc kustomize kustomize/overlays/prod | less
oc apply -k kustomize/overlays/prod
oc get deploy,cm -n ${LAB_USER}-kustomize-prod
```

<details><summary>prod 힌트</summary>

```yaml
namespace: ${LAB_USER}-kustomize-prod     # 실제 이름으로
replicas:
- name: kapp
  count: 3
images:
- name: lab-app
  newName: <IMG_APP 값>
  newTag: v2
configMapGenerator:
- name: kapp-config
  behavior: merge
  literals:
  - APP_MESSAGE=prod
```
</details>

### 생각해 볼 것
- configMapGenerator 는 내용이 바뀌면 이름(해시)이 바뀝니다. 그래서 ConfigMap 만 바꿔도 Deployment 가 **자동으로 롤아웃**됩니다.
- `oc delete -k kustomize/overlays/dev` 로 한 번에 삭제할 수 있습니다.

## 채점 / 정리
```bash
lab grade ex280-06
lab finish ex280-06
```
