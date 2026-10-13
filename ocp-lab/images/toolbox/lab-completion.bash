# bash completion for lab
_lab() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[1]:-}"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "init login list guide start grade finish solve status env version help" -- "$cur"))
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "$prev" in
      guide|start|grade|finish|solve)
        COMPREPLY=($(compgen -W "$(ls "${LAB_HOME:-/opt/ocp-lab}/exercises" 2>/dev/null)" -- "$cur")) ;;
    esac
  fi
}
complete -F _lab lab
