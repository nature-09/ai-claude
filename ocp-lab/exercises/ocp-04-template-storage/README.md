# ocp-04-template-storage — 템플릿으로 DB 배포, PVC 로 데이터 유지

## 목표
- OpenShift Template 의 파라미터를 확인하고 `oc process` 로 리소스를 만든다
- PVC/PV/StorageClass 관계를 이해한다
- 파드를 지워도 PVC 의 데이터가 남는 것을 확인한다

## 시작
```bash
lab start ocp-04
eval "$(lab env)"
cd ${LAB_WORKDIR}/ocp-04-template-storage
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 템플릿 등록 | `mysql-persistent-template.yaml` 을 프로젝트 `${LAB_USER}-db` 에 생성 |
| 2 | 템플릿으로 배포 | `MYSQL_USER=labuser`, `MYSQL_PASSWORD=labpass`, `MYSQL_DATABASE=items` |
| 3 | 데이터 입력 | 테이블 `products(id, name)` 만들고 `name='persist-test'` 행 입력 |
| 4 | 첫 파드 기록 | 아래 "첫 파드 기록" 명령 실행 (채점용) |
| 5 | 파드 재생성 | mysql 파드를 삭제하고 데이터가 남아 있는지 확인 |

### 템플릿 다루기
```bash
oc process --parameters -f mysql-persistent-template.yaml     # 파라미터 목록
oc create -f mysql-persistent-template.yaml                    # 프로젝트에 등록
oc get templates
oc process mysql-persistent-lab -p MYSQL_USER=labuser -p MYSQL_PASSWORD=labpass \
   -p MYSQL_DATABASE=items | oc apply -f -
# 같은 방법: oc new-app --template=mysql-persistent-lab -p MYSQL_USER=labuser ...
# 클러스터 공용 템플릿 보기: oc get templates -n openshift
```

### 스토리지 확인
```bash
oc get pvc,pv
oc get storageclass                      # (default) 표시 확인
oc describe pvc mysql                    # Bound 될 때까지 (WaitForFirstConsumer 면 파드가 떠야 Bound)
oc rollout status deployment/mysql
```

### 데이터 입력
```bash
oc rsh deployment/mysql
  mysql -u labuser -plabpass items
  mysql> create table products (id int auto_increment primary key, name varchar(50));
  mysql> insert into products(name) values ('persist-test');
  mysql> select * from products; 
  mysql> exit
  exit
```

### 첫 파드 기록 (채점용)
```bash
oc annotate secret/mysql lab/first-pod=$(oc get pod -l app=mysql -o name | cut -d/ -f2) --overwrite
```

### 파드 삭제 후 확인
```bash
oc delete pod -l app=mysql
oc get pods -w                       # 새 파드가 같은 PVC 를 다시 붙임 (Ctrl+C)
oc exec deploy/mysql -- bash -c 'mysql -u labuser -plabpass items -e "select * from products"'
```

## 생각해 볼 것
- 템플릿의 Deployment 는 `strategy: Recreate` 입니다. RollingUpdate 라면 RWO 볼륨에서 어떤 문제가 생길까요?
- `MYSQL_PASSWORD` 를 지정하지 않으면 `generate: expression` 으로 자동 생성됩니다. 어디서 확인할 수 있을까요? (`oc extract secret/mysql --to=-`)

## 채점 / 정리
```bash
lab grade ocp-04
lab finish ocp-04
```
