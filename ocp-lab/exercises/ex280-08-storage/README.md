# ex280-08-storage — 영구 스토리지

## 목표 (EX280: Manage storage for application data)
- StorageClass, PV, PVC 관계를 이해한다
- 실행 중인 Deployment 에 PVC 를 추가하고 데이터가 유지되는지 확인한다
- ConfigMap, emptyDir 볼륨과의 차이를 이해한다

## 시작
```bash
lab start ex280-08
eval "$(lab env)"
```
`files` 앱(Deployment/Service/Route)이 준비되어 있습니다. 앱은 `/data` 디렉터리에 파일을 저장합니다.
```bash
HOST=$(oc get route files -o jsonpath='{.spec.host}')
curl -s -X POST --data-binary "임시 데이터" "http://$HOST/data?file=tmp.txt"
curl -s http://$HOST/data
oc delete pod -l app=files; sleep 15; curl -s http://$HOST/data      # 파일이 사라짐 (컨테이너 파일시스템)
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 스토리지 확인 | 기본 StorageClass, provisioner, volumeBindingMode, reclaimPolicy 확인 |
| 2 | PVC 추가 | 이름 `files-data`, 1Gi, RWO, 기본 StorageClass, `files` 의 `/data` 에 마운트 |
| 3 | 데이터 저장 | `/data/hello.txt` 에 `${LAB_USER}` 저장 (아래 curl) |
| 4 | 유지 확인 | 파드를 삭제한 뒤에도 파일이 남는지 확인 |
| 5 | ConfigMap 볼륨 | ConfigMap `web-content`(키 `index.html`) 를 `/etc/app-config` 에 마운트 |
| 6 | emptyDir | 볼륨 이름 `cache`, emptyDir, `/cache` 에 마운트 |

<details><summary>힌트</summary>

```bash
oc get storageclass
oc describe storageclass <기본 SC>

oc set volumes deployment/files --add --name=data --type=pvc --claim-name=files-data \
   --claim-size=1Gi --claim-mode=rwo --mount-path=/data
#   (--claim-class=<SC 이름> 으로 StorageClass 지정 가능. 생략하면 기본 SC)
oc get pvc,pv
oc rollout status deployment/files

curl -s -X POST --data-binary "${LAB_USER}" "http://$HOST/data?file=hello.txt"
oc delete pod -l app=files
oc rollout status deployment/files
curl -s "http://$HOST/data?file=hello.txt"

oc create configmap web-content --from-literal=index.html="hello ${LAB_USER}"
oc set volumes deployment/files --add --name=web --type=configmap --configmap-name=web-content --mount-path=/etc/app-config
oc set volumes deployment/files --add --name=cache --type=emptyDir --mount-path=/cache
oc set volumes deployment/files            # 볼륨 목록
```
</details>

## 알아둘 것
- `oc set volumes --add --claim-size` 는 PVC 가 없으면 **새로 만듭니다**. PVC 를 YAML 로 먼저 만들어도 됩니다:
  ```yaml
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata: {name: files-data}
  spec:
    accessModes: [ReadWriteOnce]
    resources: {requests: {storage: 1Gi}}
    # storageClassName: <SC>
  ```
- **RWO** 볼륨은 한 노드에만 붙습니다. `RollingUpdate` 전략이면 새 파드가 다른 노드에 뜰 때 붙지 못해 멈출 수 있어 `files` 는 `Recreate` 전략입니다.
- `reclaimPolicy: Delete` 면 PVC 를 지울 때 PV 와 실제 데이터도 지워집니다.
- StorageClass 에 `allowVolumeExpansion: true` 면 `oc patch pvc files-data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'` 로 확장할 수 있습니다.
- 볼륨 제거: `oc set volumes deployment/files --remove --name=cache`
- 기본 StorageClass 변경(강사): `oc patch storageclass <SC> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'`

## 채점 / 정리
```bash
lab grade ex280-08
lab finish ex280-08
```
