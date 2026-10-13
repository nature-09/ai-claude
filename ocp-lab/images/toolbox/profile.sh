# ocp-lab 툴박스 로그인 셸 설정
export LAB_HOME=/opt/ocp-lab
export EDITOR=vi
case "$-" in *i*) ;; *) return 0 ;; esac

if command -v lab >/dev/null 2>&1; then
  eval "$(lab env 2>/dev/null)" || true
fi
PS1='[\[\e[36m\]ocp-lab\[\e[0m\] ${LAB_USER:-?} \W]\$ '

if [ -z "${OCP_LAB_MOTD_SHOWN:-}" ]; then
  export OCP_LAB_MOTD_SHOWN=1
  cat <<MOTD

  ┌──────────────────────────────────────────────────────────────┐
  │  OpenShift 실습 툴박스  (ocp-lab $(cat /opt/ocp-lab/VERSION))
  │
  │  처음이라면:  lab init <이름>   →  lab login   →  lab list
  │  실습 진행:   lab start <ID> / lab guide <ID> / lab grade <ID> / lab finish <ID>
  │  작업 파일:   /work (호스트의 ~/ocp-lab-home 에 저장됨)
  └──────────────────────────────────────────────────────────────┘
MOTD
  if ! oc whoami >/dev/null 2>&1; then echo "  ※ 아직 OCP 에 로그인하지 않았습니다 (lab login)"; fi
  echo
fi
