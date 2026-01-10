# ==========================================
# YUKO MOBILE CONFIG (BASH)
# ==========================================

# --- NAV & BASICS ---
alias l='ls'
alias cs="cd /data/data/com.termux/files/home/storage/shared/Download"
alias vwi='vim ~/yang_wiki/index.md'
alias addmd="find . -type f -exec mv '{}' '{}'.pdf \;"

# --- PROJECT BRAID ---
projects=("s:Software" "y:Yuko's Workshop" "w:Re-l" "e:emporium" "r:Radiant-Pact" "l:Life")

# PROJECT CRUD ENGINE
_proj() {
    local p=$1
    local action=$2
    shift 2
    case $action in
        c) task add project:"$p" "$@" ;;  
        r) task project:"$p" list ;;      
        u) task "$1" modify "${@:2}" ;;     
        d) task "$1" delete ;;            
        *) task project:"$p" "$action" "$@" ;; 
    esac
}

# CONTEXT SWITCH ENGINE
_ctx() {
    local p=$1
    task context define "$p" project:"$p" 2>/dev/null
    task context "$p"
    clear
    echo -e "\033[1;33mContext: $p\033[0m"
    report
}

# ALIAS GENERATOR
for entry in "${projects[@]}"; do
    key="${entry%%:*}"
    name="${entry#*:}"
    alias "${key}c"="_proj $name c"
    alias "${key}r"="_proj $name r"
    alias "${key}u"="_proj $name u"
    alias "${key}d"="_proj $name d"
    alias "${key}x"="_ctx $name"
done

# --- TASK ENGINES ---
alias ic='task add +inbox'
alias ir='task +inbox list'
alias ip='task modify'
alias review='task status:pending age.gt:2w list'

# TRIAGE LOOP
it() {
    local id=$(task +inbox _ids | awk -F',' '{print $1}')
    if [ -z "$id" ]; then
        echo -e "\033[1;32m✅ Inbox empty\033[0m"
    else
        task "$id" info
        echo -e "\n\033[1;36mMAP:\033[0m [s] System | [t] Taskwiki | [w] Work | [h] Home | [l] Life | [r] Radiant"
        echo -n "🚀 Move to (Key/Name/q): "
        read input
        [[ "$input" == "q" ]] && return
        case "$input" in
            s) proj="SystemRepair" ;;
            t) proj="Taskwiki" ;;
            w) proj="Work" ;;
            h) proj="Home" ;;
            l) proj="Life" ;;
            r) proj="Radiant-Pact" ;;
            *) proj="$input" ;;
        esac
        task "$id" modify project:"$proj" -inbox
    fi
}

# --- REPORTING ---

# PROGRESS BAR
get_task_progress() {
    local done=$(task end:today status:completed count)
    local del=$(task end:today status:deleted count)
    local total=$((done + del))
    if [ "$total" -eq 0 ]; then
        echo -e "\033[1;30m[----------] 0%\033[0m"
        return
    fi
    local percent=$((done * 100 / total))
    local fill=$((percent / 10))
    local bar="\033[1;32m"
    for ((i=0; i<fill; i++)); do bar+="="; done
    echo -e "[$bar\033[1;30m$(printf '%*s' $((10-fill)) | tr ' ' '-')] $percent%"
}

# DASHBOARD
report() {
    echo -e "\033[1;35m--- PERFORMANCE ---\033[0m"
    get_task_progress
    local ctx=$(task _get rc.context)
    [[ -z "$ctx" ]] && echo "Context: Global" || echo -e "Context: \033[1;33m$ctx\033[0m"
    echo -e "\n\033[1;34mClocked In:\033[0m"
    task +ACTIVE list || echo "  (None)"
}

# HEALTH MAP
alias tll='task summary; echo -e "\n--- GAPS ---"; task gprojects'

# DAILY RECAP
tlo() {
    clear
    echo -e "\033[1;35m=== DAILY RECAP ===\033[0m"
    echo -e "\n\033[1;32m🏆 DONE TODAY:\033[0m"
    task end:today status:completed export | jq -r '.[].description' | sed 's/^/ [✓] /'
    echo -e "\n\033[1;36m🚀 TOMORROW:\033[0m"
    task +READY +PENDING limit:3
    task sync
}

