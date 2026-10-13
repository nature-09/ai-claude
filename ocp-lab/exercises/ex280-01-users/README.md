# ex280-01-users — HTPasswd ID 공급자와 사용자 관리

> **공유 클러스터 주의**: OAuth 설정(`oauth/cluster`)은 모든 수강생이 함께 씁니다.
> - 반드시 **내 IdP 하나를 목록에 추가**하는 방식(`oc patch --type=json ... /-`)으로 수정하세요.
> - `oc apply -f oauth.yaml` 로 통째로 덮어쓰면 다른 사람의 IdP 가 지워질 수 있습니다.
> - IdP 를 바꿀 때마다 oauth-openshift 파드가 다시 시작되어 1~3분간 로그인이 느릴 수 있습니다.

## 목표 (EX280: Manage authentication and authorization)
- htpasswd 파일과 Secret 으로 HTPasswd ID 공급자를 구성한다
- 사용자에게 cluster-admin 권한을 준다
- 비밀번호 변경, 사용자 삭제(User/Identity 정리)를 한다

## 시작
```bash
lab start ex280-01
eval "$(lab env)"
cd ${LAB_WORKDIR}/ex280-01-users
```

## 과제

| # | 할 일 | 조건 |
|---|---|---|
| 1 | htpasswd 파일 | 사용자 `${LAB_USER}-admin`(redhat123), `${LAB_USER}-dev`(redhat123), `${LAB_USER}-qa`(qa123), bcrypt(-B) |
| 2 | Secret | `openshift-config` 네임스페이스, 이름 `${LAB_USER}-htpasswd`, 키 `htpasswd` |
| 3 | IdP 추가 | OAuth 에 이름 `${LAB_USER}-htpasswd`, 유형 HTPasswd |
| 4 | 권한 | `${LAB_USER}-admin` 에 `cluster-admin` |
| 5 | 로그인 시험 | 세 사용자로 각각 로그인해 본다 |
| 6 | 비밀번호 변경 | `${LAB_USER}-dev` 비밀번호를 `developer123` 으로 변경 |
| 7 | 사용자 삭제 | `${LAB_USER}-qa` 를 htpasswd 에서 지우고 User, Identity 객체도 삭제 |

## 풀이 가이드

### 1~2. htpasswd 파일과 Secret
```bash
htpasswd -c -B -b users.htpasswd ${LAB_USER}-admin redhat123
htpasswd -B -b users.htpasswd ${LAB_USER}-dev redhat123
htpasswd -B -b users.htpasswd ${LAB_USER}-qa qa123
cat users.htpasswd

oc create secret generic ${LAB_USER}-htpasswd --from-file=htpasswd=users.htpasswd -n openshift-config
```

### 3. OAuth 에 IdP 추가
시험에서는 보통 `oc edit oauth cluster` 나 웹 콘솔(**Administration → Cluster Settings → Configuration → OAuth → Add → HTPasswd**)을 씁니다.
공유 클러스터에서는 아래처럼 **추가(add)** 패치를 쓰세요.
```bash
oc get oauth cluster -o yaml          # 현재 목록 확인

oc patch oauth cluster --type=json -p '[{"op":"add","path":"/spec/identityProviders/-","value":{
  "name":"'${LAB_USER}'-htpasswd","mappingMethod":"claim","type":"HTPasswd",
  "htpasswd":{"fileData":{"name":"'${LAB_USER}'-htpasswd"}}}}]'

oc get pods -n openshift-authentication -w     # 새 파드로 교체될 때까지 (Ctrl+C)
```
참고로 단독 클러스터에서 `oc edit oauth cluster` 로 쓰는 YAML 은 다음과 같습니다.
```yaml
spec:
  identityProviders:
  - name: myusers
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
```

### 4. 권한
```bash
oc adm policy add-cluster-role-to-user cluster-admin ${LAB_USER}-admin
```
(사용자 객체가 아직 없다는 경고는 무시해도 됩니다. 처음 로그인할 때 User 가 만들어집니다.)

### 5. 로그인 시험 (현재 로그인을 유지하려고 별도 kubeconfig 사용)
```bash
API=$(oc whoami --show-server)
oc login $API -u ${LAB_USER}-admin -p redhat123 --kubeconfig=/tmp/kc-test --insecure-skip-tls-verify
oc whoami --kubeconfig=/tmp/kc-test
oc get nodes --kubeconfig=/tmp/kc-test          # admin 은 성공
oc login $API -u ${LAB_USER}-dev -p redhat123 --kubeconfig=/tmp/kc-test --insecure-skip-tls-verify
oc get nodes --kubeconfig=/tmp/kc-test          # dev 는 Forbidden
oc login $API -u ${LAB_USER}-qa -p qa123 --kubeconfig=/tmp/kc-test --insecure-skip-tls-verify
oc get users,identities | grep ${LAB_USER}
```

### 6~7. 비밀번호 변경과 사용자 삭제 — Secret 에서 파일을 꺼내 고치고 다시 넣기
```bash
oc extract secret/${LAB_USER}-htpasswd -n openshift-config --to=. --confirm   # ./htpasswd
htpasswd -B -b htpasswd ${LAB_USER}-dev developer123
htpasswd -D htpasswd ${LAB_USER}-qa
oc set data secret/${LAB_USER}-htpasswd -n openshift-config --from-file=htpasswd=htpasswd

oc delete user ${LAB_USER}-qa
oc delete identity ${LAB_USER}-htpasswd:${LAB_USER}-qa
```
Secret 이 바뀌면 oauth 파드가 다시 시작됩니다. 1~2분 뒤 새 비밀번호로 로그인해 보세요.

## 시험에 자주 나오는 것 (단독 클러스터에서만 — 공유 클러스터에서는 하지 마세요)
- **kubeadmin 삭제**: cluster-admin 사용자로 로그인되는 것을 확인한 뒤
  `oc delete secret kubeadmin -n kube-system` (되돌릴 수 없음)
- IdP 이름·Secret 이름은 문제에 나온 그대로 써야 채점됩니다.

## 채점 / 정리
```bash
lab grade ex280-01
lab finish ex280-01          # IdP, Secret, 사용자, 권한 정리
```
