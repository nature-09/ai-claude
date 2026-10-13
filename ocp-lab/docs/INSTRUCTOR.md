# 강사 가이드

## 공유 클러스터 운영 원칙

여러 수강생이 한 클러스터를 쓰므로 모든 리소스는 수강생 이름(`LAB_USER`, 예: `student03`)을 접두어로 씁니다.

| 대상 | 이름 규칙 |
|---|---|
| 네임스페이스 | `student03-<실습>` (라벨 `ocp-lab/student=student03`) |
| OAuth IdP / Secret | `student03-htpasswd`, `student03-exam` / `openshift-config` 의 같은 이름 Secret |
| 사용자·그룹 | `student03-admin`, `student03-dev`, `student03-developers` ... |
| ClusterResourceQuota | `student03-crq` |
| 프로젝트 템플릿 | `openshift-config/student03-project-request` |
| 라우트 호스트 | `student03-edge.apps...` 등 |

### 공유 모드에서 강사 시연으로 돌리는 항목 (`LAB_SHARED=true`)
| 실습 | 항목 | 이유 |
|---|---|---|
| ex280-02 | self-provisioner 제거 | 모든 사용자의 프로젝트 생성 권한이 바뀜 |
| ex280-04 | `projects.config` 에 템플릿 지정 | 모든 신규 프로젝트에 영향, openshift-apiserver 재시작 |
| ex280-01 | kubeadmin 삭제 | 되돌릴 수 없음 — 가이드 설명만 |

수강생은 템플릿 작성·검증까지 하고, 강사가 한 명의 템플릿으로 적용 → 확인 → 원복을 시연합니다.
```bash
# 시연 (예: student01 의 템플릿)
oc patch project.config.openshift.io cluster --type=merge -p '{"spec":{"projectRequestTemplate":{"name":"student01-project-request"}}}'
oc new-project demo-tpl && oc get quota,limitrange,networkpolicy -n demo-tpl
oc patch project.config.openshift.io cluster --type=json -p '[{"op":"remove","path":"/spec/projectRequestTemplate"}]'
oc delete project demo-tpl
```

### OAuth 동시 수정
ex280-01, ex280-15 는 수강생마다 IdP 를 추가합니다. `oc patch --type=json` 의 add(`/-`)는 안전하지만,
`oc apply -f oauth.yaml` 로 통째로 덮어쓰면 다른 사람의 IdP 가 사라질 수 있습니다 (가이드에 경고 있음).
IdP 변경마다 oauth-openshift 가 재시작되므로 20명이 동시에 하면 수 분간 로그인이 느려질 수 있습니다.
IdP 가 사라졌다면 `lab-admin students create` 를 다시 실행하면 수강생 IdP 가 복구됩니다(비밀번호는 다시 생성되니 같은 비밀번호를 지정하세요).

## 진도 확인

```bash
lab-admin progress ex280-05                      # 수강생 전체, 한 실습
lab-admin progress all student01 student02       # 특정 수강생, 전체 실습
LAB_USER=student07 lab grade ex280-09            # 한 명 상세
```
수강생의 채점 기록은 각자 `~/.ocp-lab/results.log` 에도 남습니다.

## 모범 답안 / 사전 검증
강의 전 강사 계정으로 모든 실습을 돌려 보세요.
```bash
export LAB_USER=teacher LAB_YES=1
for ex in $(ls /opt/ocp-lab/exercises); do
  lab start $ex && lab solve $ex && lab grade $ex; lab finish $ex
done 2>&1 | tee ~/ocp-lab-selftest.log
```

## 정리
```bash
lab-admin cleanup student05          # 한 명: 네임스페이스, IdP, Secret, 사용자, 그룹, CRQ, 템플릿, 클러스터 권한
lab-admin cleanup --all              # 모든 수강생
lab-admin students delete            # 수강생 계정 자체 삭제
```

## 실습 순서 제안 (3일 과정 예)

| 일차 | 오전 | 오후 |
|---|---|---|
| 1일 | ocp-01 ~ ocp-03 (CLI, 배포, 설정) | ocp-04 ~ ocp-06 (템플릿/스토리지, 빌드, 장애 진단) |
| 2일 | ex280-01 ~ 04 (인증, RBAC, 쿼터, 템플릿) | ex280-05 ~ 08 (배포/롤백, Helm/Kustomize, 안정성, 스토리지) |
| 3일 | ex280-09 ~ 14 (TLS, 네트워크 정책, TCP 노출, SCC, Job, 오퍼레이터) | ex280-15 모의고사 (2시간) + 리뷰 |

## EX280 출제 범위와 실습 대응

| EX280 목표 | 실습 |
|---|---|
| Manage OpenShift Container Platform (CLI/콘솔, 리소스 조회, 문제 해결) | ocp-01, ocp-02, ocp-06 |
| Deploy applications (이미지, 템플릿, Helm, Kustomize) | ocp-02, ocp-04, ex280-05, ex280-06 |
| Manage storage for application configuration and data | ocp-03, ocp-04, ex280-08 |
| Configure applications for reliability (프로브, 리소스, HPA) | ex280-07 |
| Manage application updates (이미지 태그/digest, 이미지 스트림, 롤백) | ex280-05, ocp-05 |
| Manage authentication and authorization (HTPasswd, 사용자/그룹, RBAC) | ex280-01, ex280-02 |
| Configure network security (TLS 라우트, NetworkPolicy, 서비스 CA) | ex280-09, ex280-10 |
| Expose non-HTTP/SNI applications (LoadBalancer, NodePort) | ex280-11 |
| Enable developer self-service (쿼터, LimitRange, 프로젝트 템플릿, self-provisioner) | ex280-03, ex280-04, ex280-02 |
| Manage OpenShift operators (OLM, CLI/콘솔 설치) | ex280-14 |
| Configure application security (SCC, SA, Secret, Job) | ex280-12, ex280-13 |

> 출제 범위는 Red Hat 이 갱신하므로 강의 전 공식 EX280 페이지의 최신 목표와 비교하세요.
