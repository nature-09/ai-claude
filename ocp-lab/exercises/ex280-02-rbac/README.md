# ex280-02-rbac — 그룹과 RBAC

## 목표 (EX280: Manage authentication and authorization / Enable developer self-service)
- 그룹을 만들고 사용자를 넣는다
- 클러스터 역할(admin, edit, view)을 프로젝트 단위로 사용자·그룹에 바인딩한다
- 사용자 정의 Role 을 만들어 서비스 어카운트에 준다
- 일반 사용자의 프로젝트 생성(self-provisioner) 권한을 제거한다

> 사용자 `${LAB_USER}-admin`, `${LAB_USER}-dev`, `${LAB_USER}-qa` 는 ex280-01 에서 만든 사용자입니다.
> 사용자 객체가 없어도 권한 바인딩·채점은 가능합니다 (`oc auth can-i --as` 로 확인).

## 시작
```bash
lab start ex280-02
eval "$(lab env)"
```
프로젝트 `${LAB_USER}-rbac-dev`, `${LAB_USER}-rbac-prod` 가 준비됩니다.

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | 그룹 | `${LAB_USER}-developers` ← `${LAB_USER}-dev`, `${LAB_USER}-qa-team` ← `${LAB_USER}-qa` |
| 2 | developers | `${LAB_USER}-rbac-dev` 에서 `edit` |
| 3 | qa-team | `${LAB_USER}-rbac-dev`, `${LAB_USER}-rbac-prod` 에서 `view` |
| 4 | admin 사용자 | `${LAB_USER}-admin` 이 `${LAB_USER}-rbac-prod` 의 `admin` |
| 5 | 사용자 정의 Role | `${LAB_USER}-rbac-prod` 에 Role `pod-reader`(pods: get, list, watch), 서비스 어카운트 `monitor` 에 바인딩 |
| 6 | self-provisioner | (단독 클러스터) 인증된 사용자가 프로젝트를 만들지 못하게 하고 자동 복구도 막기 — **공유 클러스터에서는 강사 시연** |

## 풀이 가이드
```bash
# 1. 그룹
oc adm groups new ${LAB_USER}-developers ${LAB_USER}-dev
oc adm groups new ${LAB_USER}-qa-team
oc adm groups add-users ${LAB_USER}-qa-team ${LAB_USER}-qa
oc get groups | grep ${LAB_USER}

# 2~4. 역할 바인딩
oc policy add-role-to-group edit ${LAB_USER}-developers -n ${LAB_USER}-rbac-dev
oc policy add-role-to-group view ${LAB_USER}-qa-team -n ${LAB_USER}-rbac-dev
oc policy add-role-to-group view ${LAB_USER}-qa-team -n ${LAB_USER}-rbac-prod
oc policy add-role-to-user admin ${LAB_USER}-admin -n ${LAB_USER}-rbac-prod
oc get rolebindings -n ${LAB_USER}-rbac-prod -o wide

# 5. 사용자 정의 Role + 서비스 어카운트
oc create role pod-reader --verb=get,list,watch --resource=pods -n ${LAB_USER}-rbac-prod
oc create serviceaccount monitor -n ${LAB_USER}-rbac-prod
oc policy add-role-to-user pod-reader -z monitor --role-namespace=${LAB_USER}-rbac-prod -n ${LAB_USER}-rbac-prod
#   (같은 의미: oc create rolebinding monitor-pod-reader --role=pod-reader --serviceaccount=${LAB_USER}-rbac-prod:monitor)

# 권한 확인
oc auth can-i create deployments -n ${LAB_USER}-rbac-dev --as=${LAB_USER}-dev --as-group=${LAB_USER}-developers
oc auth can-i list pods -n ${LAB_USER}-rbac-prod --as=system:serviceaccount:${LAB_USER}-rbac-prod:monitor
oc adm policy who-can delete pods -n ${LAB_USER}-rbac-prod
```

### 6. self-provisioner 제거 (단독 클러스터 / 강사 시연)
```bash
oc describe clusterrolebinding self-provisioners       # 기본: system:authenticated:oauth 그룹
oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
oc annotate clusterrolebinding self-provisioners rbac.authorization.kubernetes.io/autoupdate=false --overwrite
# 다시 허용:  oc adm policy add-cluster-role-to-group self-provisioner system:authenticated:oauth
# 특정 그룹만 허용: oc adm policy add-cluster-role-to-group self-provisioner <그룹>
```
`autoupdate=false` 를 빠뜨리면 API 서버가 재시작될 때 기본값으로 되돌아갑니다.

### 웹 콘솔
**User Management → Groups / RoleBindings**, 프로젝트 화면의 **Access** 탭에서도 바인딩을 관리할 수 있습니다.

## 채점 / 정리
```bash
lab grade ex280-02
lab finish ex280-02
```
