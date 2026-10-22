# LinXterm - startup file of the local bash terminals.
# Reads the usual ~/.bashrc first, then sets the MobaXterm prompt:
#
#   [2024-10-22 14:12.42]  ~/projects
#   [user.host] ➤
#
# Settings > Configuration > Terminal disables it (plain ~/.bashrc prompt).

if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
elif [ -f /etc/bashrc ]; then
    . /etc/bashrc
elif [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

# green arrow after a successful command, red after a failure; LinXterm is
# told that the prompt is back with the exit status (desktop notifications
# when a long command ends, VTE >= 0.78)
__linxterm_status() {
    local s=$?
    if [ "$s" = 0 ]; then __linxterm_arrow='1;32'; else __linxterm_arrow='1;31'; fi
    if [ "${VTE_VERSION:-0}" -ge 7800 ]; then
        printf '\e]666;vte.ext.linxterm.prompt=%s\e\\' "$s"
    fi
    return $s
}

if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND=(__linxterm_status "${PROMPT_COMMAND[@]}")
else
    PROMPT_COMMAND="__linxterm_status${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi

PS1='\n\[\e[0;37m\][\D{%Y-%m-%d %H:%M.%S}]\[\e[0m\]  \[\e[1;34m\]\w\[\e[0m\]\n\[\e[0;37m\][\u.\h]\[\e[0m\] \[\e[${__linxterm_arrow:-1;32}m\]➤\[\e[0m\] '
