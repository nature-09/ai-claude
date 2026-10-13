# 폐쇄망 OCP 적용 절차 (체크리스트)

이미 설치된 폐쇄망 OCP 4.19+ 에 ocp-lab 실습 환경을 올리는 전체 순서입니다.
각 단계의 **확인** 명령이 통과하면 다음 단계로 넘어갑니다. 명령별 상세 설명은 [INSTALL.md](INSTALL.md) 를 참고하세요.

> **사내 메신저와의 관계**: 같은 저장소에 있을 뿐 **서로 독립된 프로젝트**입니다.
> ocp-lab 은 메신저 코드·이미지·Helm 차트를 쓰지 않고, 번들(`ocp-lab-bundle-*.tar.gz`)도 따로 만듭니다.
> 같은 클러스터에 둘 다 올려도 충돌하지 않습니다 (메신저: `messenger` 네임스페이스 / ocp-lab: `student01-*` 등 수강생 접두어,
> 레지스트리 경로도 `messenger/...` 와 `ocp-lab/...` 로 분리). 실습 클러스터에 메신저를 꼭 올릴 필요는 없습니다.

## 전체 흐름

| 단계 | 위치 | 담당 | 소요 |
|---|---|---|---|
| 0. 사전 확인 | 폐쇄망 | 인프라 | 30분 |
| 1. 번들 생성 | 인터넷 환경 | 강사/인프라 | 30분~1시간 |
| 2. (선택) 오퍼레이터 미러링 | 인터넷 → 폐쇄망 | 인프라 | 1~2시간 |
| 3. 반입 | 매체 반출입 | 보안 절차 | 사내 규정 |
| 4. 이미지 업로드 | bastion | 인프라 | 20분 |
| 5. 클러스터 사전 구성 | bastion (cluster-admin) | 인프라 | 30분~1시간 |
| 6. lab 도구 설치 | bastion (root) | 인프라 | 10분 |
| 7. 점검 | bastion | 강사 | 10분 |
| 8. 수강생 계정 | bastion | 강사 | 10분 |
| 9. 사전 검증 (전 실습 자동 풀이) | bastion | 강사 | 1~2시간 |
| 10. 교육 진행 / 종료 정리 | — | 강사 | — |

---

## 0. 사전 확인 (폐쇄망)

| 항목 | 확인 방법 | 필요 이유 |
|---|---|---|
| OCP 4.19 이상, 모든 ClusterOperator 정상 | `oc get clusterversion; oc get co` | 전체 |
| 사내 레지스트리 주소·계정, 조직 `ocp-lab` 생성 권한 | 레지스트리 관리자 | 이미지 업로드 |
| bastion 에서 레지스트리 접속 | `curl -I https://<레지스트리>/v2/` | 업로드, lab-shell |
| bastion 에서 API / 라우트 DNS | `dig api.<클러스터>`, `dig test.apps.<클러스터>` | 로그인, 라우트 채점 |
| bastion → 노드 NodePort(30000-32767) 방화벽 | 네트워크 담당 | ex280-11 |
| 기본 StorageClass | `oc get sc` 에 `(default)` | ocp-04, ex280-08, 15 |
| 메트릭(HPA) | `oc get apiservice v1beta1.metrics.k8s.io` | ex280-07 |
| 노드 대역의 미사용 IP 몇 개 (선택) | 네트워크 담당 | MetalLB, ex280-11 |
| bastion 패키지 | `rpm -q podman skopeo jq openssl curl httpd-tools` | 도구 |
| bastion 디스크 여유 | 번들 압축 해제 + 이미지 적재 약 6GB | 업로드 |

## 1. 번들 생성 (인터넷 환경)

```bash
git clone <저장소> && cd ai-claude/ocp-lab
podman login registry.redhat.io                    # Red Hat 계정 (MySQL 이미지)
OC_CHANNEL=stable-4.19 ./scripts/export-bundle.sh  # 클러스터 마이너 버전에 맞춤
ls -lh dist/                                       # ocp-lab-bundle-1.0.0.tar.gz, .sha256
```
**확인**: 오류 없이 `완료` 출력, `.sha256` 파일 생성.

## 2. (선택) 오퍼레이터 미러링

ex280-14(오퍼레이터 설치) 는 `rhbk-operator` 가 카탈로그에 있어야 합니다. MetalLB 는 ex280-11 LoadBalancer 용(권장).
```bash
# 인터넷 환경
oc mirror -c mirror/imageset-config.yaml file:///data/oc-mirror --v2
```
반입 후 7단계 전에 폐쇄망에서 업로드·적용합니다 → [OPERATORS.md](OPERATORS.md)

## 3. 반입
`ocp-lab-bundle-1.0.0.tar.gz`, `.sha256` (+ oc-mirror 결과) 를 사내 절차로 bastion 에 옮깁니다.

## 4. 이미지 업로드 (bastion)

```bash
sha256sum -c ocp-lab-bundle-1.0.0.tar.gz.sha256
tar xzf ocp-lab-bundle-1.0.0.tar.gz && cd ocp-lab-bundle-1.0.0
podman login registry.corp.local:5000
REGISTRY=registry.corp.local:5000 ./import-bundle.sh       # 사설 CA 미신뢰 시 TLS_VERIFY=false
```
**확인**: `skopeo list-tags docker://registry.corp.local:5000/ocp-lab/lab-app` → `v1 v2 v3 legacy`
레지스트리에서 `ocp-lab` 조직의 저장소를 **public** 으로 바꾸면 5-2 단계가 필요 없습니다.

## 5. 클러스터 사전 구성 (cluster-admin)

### 5-1. 레지스트리 CA 를 이미지 API 에 신뢰 (ImageStream import, S2I 빌드용)
노드의 이미지 pull 은 설치 시 넣은 CA 로 되지만, `oc import-image` 는 별도 설정이 필요한 경우가 많습니다.
```bash
# 키 이름: 호스트명, 포트는 ':' 대신 '..'
oc create configmap registry-ca -n openshift-config \
  --from-file=registry.corp.local..5000=/etc/pki/ca-trust/source/anchors/registry-ca.crt
oc patch image.config.openshift.io/cluster --type=merge \
  -p '{"spec":{"additionalTrustedCA":{"name":"registry-ca"}}}'
```

### 5-2. 저장소가 private 이면 글로벌 pull secret 에 인증 추가
```bash
oc get secret/pull-secret -n openshift-config --template='{{index .data ".dockerconfigjson" | base64decode}}' > pull.json
oc registry login --registry=registry.corp.local:5000 --auth-basic='<id>:<pw>' --to=pull.json
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull.json
rm -f pull.json
```
(노드에 반영되면서 MachineConfigPool 이 갱신될 수 있습니다 — `oc get mcp` 로 완료 확인)

### 5-3. 내부 이미지 레지스트리 (ocp-05 빌드 실습)
베어메탈/폐쇄망 설치 직후에는 `Removed` 인 경우가 많습니다.
```bash
oc get configs.imageregistry.operator.openshift.io cluster -o jsonpath='{.spec.managementState}{"\n"}'
# PVC 사용 (RWO 스토리지면 replicas 1 + Recreate)
oc patch configs.imageregistry.operator.openshift.io cluster --type=merge -p \
 '{"spec":{"managementState":"Managed","replicas":1,"rolloutStrategy":"Recreate","storage":{"pvc":{"claim":""}}}}'
# 실습 전용으로 영구 저장이 필요 없으면: "storage":{"emptyDir":{}}
oc get pods -n openshift-image-registry
```

### 5-4. 폐쇄망 OperatorHub 정리, 카탈로그 적용 (2단계를 했다면)
```bash
oc patch operatorhub cluster --type=merge -p '{"spec":{"disableAllDefaultSources":true}}'
oc apply -f /data/oc-mirror/working-dir/cluster-resources/
oc get packagemanifests -n openshift-marketplace | grep -E 'rhbk|metallb'
```

### 5-5. (권장) MetalLB
[OPERATORS.md](OPERATORS.md) 대로 오퍼레이터 설치 후, 6단계를 마치고 `lab-admin metallb <시작IP-끝IP>`.

**확인**: `oc get co` 모두 정상, image-registry 파드 Running.

## 6. lab 도구 설치 (bastion, root)

```bash
sudo ./install-bastion.sh --registry registry.corp.local:5000 \
     --api https://api.ocp.corp.local:6443 --shared true
sudo vi /etc/ocp-lab/lab.env        # LAB_REGISTRY, LAB_API_URL, LAB_OPERATOR_PACKAGE 확인
```
수강생별 bastion 리눅스 계정 (권장):
```bash
for i in $(seq -w 1 20); do sudo useradd -m student$i && echo "student$i:<초기비번>" | sudo chpasswd; done
# 툴박스(lab-shell)를 쓸 계정은 rootless podman 용 subuid/subgid 가 자동 할당되는지 확인
grep student01 /etc/subuid
```
**확인**: `lab version`, `oc version --client`, `helm version`

## 7. 점검 (강사)

```bash
oc login -u kubeadmin https://api.ocp.corp.local:6443
lab-admin check
```
**확인**: `FAIL 0`. WARN 은 해당 실습만 제한됩니다.

| WARN | 영향 실습 | 조치 |
|---|---|---|
| 내부 이미지 레지스트리 | ocp-05 | 5-3 |
| ImageStream import 실패 | ocp-05, ex280-05 | 5-1, 5-2 |
| metrics API 없음 | ex280-07 (HPA) | monitoring 스택 확인 |
| MetalLB 미구성 | ex280-11 (LB 항목 SKIP) | 5-5 |
| 카탈로그에 rhbk-operator 없음 | ex280-14 | 2, 5-4 또는 `LAB_OPERATOR_PACKAGE` 변경 |
| htpasswd / helm 없음 | ex280-01, 06, 15 | `dnf install httpd-tools`, 번들의 helm |

## 8. 수강생 계정 (강사)

```bash
lab-admin students create 20                     # → ./ocp-lab-students.csv (무작위 비밀번호)
oc get pods -n openshift-authentication -w       # oauth 재시작 완료까지
oc login -u student01 -p <비밀번호> --kubeconfig=/tmp/t https://api...   # 로그인 시험
```
수강생 그룹은 cluster-admin 을 받습니다 (EX280 범위 실습에 필요).

## 9. 사전 검증 — 모든 실습 자동 풀이 (강사, 교육 전 필수)

```bash
export LAB_USER=teacher LAB_YES=1
for ex in $(ls /opt/ocp-lab/exercises); do
  lab start $ex && lab solve $ex && lab grade $ex; lab finish $ex
done 2>&1 | tee ~/ocp-lab-selftest.log
grep -E '결과:|FAIL' ~/ocp-lab-selftest.log
```
**확인**: 모든 실습 `모두 통과` (MetalLB 가 없으면 ex280-11 의 SKIP 은 정상).
실패 항목은 로그와 함께 개발 담당에게 전달합니다.

## 10. 교육 진행과 종료

교육 중:
```bash
lab-admin progress ex280-05          # 실습별 진도
lab-admin progress all student03     # 한 명 전체
```
수강생 안내 (화면 공유용):
```bash
ssh student01@bastion
lab init student01 && lab login && eval "$(lab env)"
lab list
lab start ocp-01 ; lab guide ocp-01 ; lab grade ocp-01 ; lab finish ocp-01
# 또는 툴박스: lab-shell
```

교육 종료 후:
```bash
lab-admin cleanup --all              # 수강생이 만든 네임스페이스·IdP·사용자·그룹·권한 정리
lab-admin students delete            # 수강생 계정 삭제
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'   # 남은 IdP 확인
oc get project.config.openshift.io cluster -o jsonpath='{.spec}{"\n"}'       # 템플릿 설정 원복 확인
```

## 업그레이드 / 재교육
새 번들로 4단계(이미지 업로드)와 6단계(도구 설치)만 다시 하면 됩니다. `/etc/ocp-lab/lab.env` 와 수강생 계정은 유지됩니다.
OCP 마이너 버전이 바뀌면 1단계에서 `OC_CHANNEL`, 2단계에서 카탈로그 태그(`v4.xx`)를 맞춰 다시 만드세요.
