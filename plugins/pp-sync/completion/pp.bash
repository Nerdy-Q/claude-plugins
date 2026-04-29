# Bash completion for the `pp` CLI (NerdyQ pp-sync plugin)
#
# Install:
#   sudo cp pp.bash /etc/bash_completion.d/pp     (system-wide)
#   cp pp.bash ~/.bash_completion.d/pp            (per-user)
# Or source directly from .bashrc:
#   source /path/to/pp.bash
#
# After install, restart the shell or:  source ~/.bashrc

# Populate COMPREPLY safely: each compgen match goes in as a single element,
# without word-splitting on whitespace or glob-expanding shell metacharacters
# that may appear in registered project names. Works on bash 3.2+ (no mapfile).
_pp_set_comp_reply() {
    local wordlist="$1" current="$2" line
    COMPREPLY=()
    while IFS= read -r line; do
        [ -n "$line" ] && COMPREPLY+=( "$line" )
    done < <(compgen -W "$wordlist" -- "$current")
}

_pp_completion() {
    local cur prev words cword
    _init_completion -n : 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    local subcommands="setup list ls show switch use status down d up u doctor commit solution-down sol-down solution-up sol-up sync-pages audit project alias help"
    local config_dir="${PP_CONFIG_DIR:-$HOME/.config/nq-pp-sync}"

    # Collect project names + aliases for completion
    _pp_projects() {
        local projects=""
        if [[ -d "$config_dir/projects" ]]; then
            projects=$(find "$config_dir/projects" -maxdepth 1 -name "*.conf" 2>/dev/null \
                | sed 's|.*/||; s|\.conf$||')
        fi
        local aliases=""
        if [[ -f "$config_dir/aliases" ]]; then
            aliases=$(cut -d= -f1 "$config_dir/aliases" 2>/dev/null)
        fi
        echo "$projects $aliases"
    }

    # Subcommand at position 1
    if [[ $cword -eq 1 ]]; then
        _pp_set_comp_reply "$subcommands" "$cur"
        return 0
    fi

    # Position 2: argument depends on subcommand
    case "${COMP_WORDS[1]}" in
        down|d|up|u|doctor|switch|use|show|sync-pages|audit|solution-down|sol-down|solution-up|sol-up)
            # First arg is a project name
            if [[ $cword -eq 2 ]]; then
                _pp_set_comp_reply "$(_pp_projects)" "$cur"
                return 0
            fi
            ;;
        project)
            # Subcommand: add | edit | remove | list
            if [[ $cword -eq 2 ]]; then
                _pp_set_comp_reply "add edit remove rm list ls" "$cur"
                return 0
            fi
            # Project arg for edit/remove
            if [[ $cword -eq 3 ]]; then
                case "${COMP_WORDS[2]}" in
                    edit|remove|rm)
                        _pp_set_comp_reply "$(_pp_projects)" "$cur"
                        return 0
                        ;;
                esac
            fi
            ;;
        alias)
            # Subcommand: add | list
            if [[ $cword -eq 2 ]]; then
                _pp_set_comp_reply "add list ls" "$cur"
                return 0
            fi
            # `alias add <new-alias> <project>` — project completion at position 4
            if [[ $cword -eq 4 && "${COMP_WORDS[2]}" = "add" ]]; then
                _pp_set_comp_reply "$(_pp_projects)" "$cur"
                return 0
            fi
            ;;
    esac

    # Position 3+: flags for some subcommands
    case "${COMP_WORDS[1]}" in
        down|d)
            _pp_set_comp_reply "--no-clean" "$cur"
            ;;
        up|u)
            _pp_set_comp_reply "--validate-only --force-bulk --bulk-threshold=" "$cur"
            ;;
        sync-pages)
            _pp_set_comp_reply "base-to-localized localized-to-base" "$cur"
            ;;
        audit)
            _pp_set_comp_reply "--severity --exit-code --json -o --output" "$cur"
            # Severity values
            if [[ "$prev" = "--severity" ]]; then
                _pp_set_comp_reply "ERROR WARN INFO" "$cur"
            fi
            ;;
    esac

    return 0
}

complete -F _pp_completion pp
