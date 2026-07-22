# ==========================================
# YUKO MOBILE CONFIG (BASH)
# ==========================================

# --- NAV & BASICS ---
alias l='ls'
alias ll='ls -ha'
alias cs="cd /data/data/com.termux/files/home/storage/shared/Download"
alias vwi='vim ~/wiki_yuko/index.md'
alias vd='vim -c "VimwikiMakeDiaryNote"'
alias t='task'
alias te='task edit' 
alias tu='task modify' 
alias tf='task done'
alias td='task delete'
alias ts='task sync'
alias cx='task context none'
alias ctx='task context define tz' # tz for task zone
alias r='report'
alias addmd="find . -type f -exec mv '{}' '{}'.pdf \;"


# --- Project Interlace ---
projects=("s:system" "t:technical" "y:yuko" "w:re-l" "e:emporium" "r:radiant" "l:life")

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
alias review='task status:pending age.gt:2w list'

# Priority Treeage
sort() {
    local primary_filter="${1:-+inbox}"
    local using_fallback=false

    echo "🧬 Taskwarrior Resilient Queue Pipeline Active."
    echo "--------------------------------------------------"

    while true; do
        # Fetch the first numeric ID matching the current filter strategy
        local id
        if [ "$using_fallback" = false ]; then
            id=$(task status:pending "$primary_filter" _ids 2>/dev/null | head -n 1)
        else
            id=$(task status:pending _ids 2>/dev/null | head -n 1)
        fi

        # If no ID is returned, handle fallback or exit
        if [ -z "$id" ]; then
            if [ "$using_fallback" = false ]; then
                echo "📭 Primary filter exhausted. Shifting to cover all remaining pending tasks..."
                using_fallback=true
                sleep 1
                continue
            else
                echo "🎉 Queue empty or no matching tasks found. Exiting pipeline."
                break
            fi
        fi

        # Display details of the current task explicitly via its numeric ID (just like `it`)
        clear
        echo "=================================================="
        task "$id" info
        echo "=================================================="

        # Prompt user for actions
        echo -e "\n[Action Options]"
        echo "  [p] Set/Change Priority (L, M, H, or blank)"
        echo "  [j] Jump/Skip to next task"
        echo "  [q] Quit pipeline"
        read -p "Select action [p/j/q]: " -n 1 -r action
        echo

        case "$action" in
            p|P)
                read -p "Enter priority (H/M/L or leave empty to clear): " prio
                prio=$(echo "$prio" | tr '[:lower:]' '[:upper:]')

                if [[ "$prio" =~ ^[HML]$ ]]; then
                    task "$id" modify priority:"$prio"
                elif [ -z "$prio" ]; then
                    task "$id" modify priority:
                else
                    echo "⚠️ Invalid priority. Skipping modification."
                    sleep 1
                    continue
                fi

                echo "✅ Task updated and advanced."
                ;;
            j|J)
                echo "⏭️ Skipping task..."
                task "$id" modify +skipped >/dev/null
                ;;
            q|Q)
                echo "🛑 Exiting queue pipeline."
                break
                ;;
            *)
                echo "⚠️ Unrecognized input. Advancing..."
                ;;
        esac

        sleep 0.5
    done
}

# Project Treeage
it() {
    local id=$(task +inbox _ids | awk -F',' '{print $1}')
    if [ -z "$id" ]; then
        echo -e "\033[1;32m✅ Inbox empty\033[0m"
    else
        task "$id" info
        echo -e "\n\033[1;36mMAP:\033[0m [s] system | [t] technical | [y] yuko | [w] re-l | [e] emporium | [l] life | [r] radiant"
        echo -n "🚀 Move to (Key/Name/q): "
        read input
        [[ "$input" == "q" ]] && return
        case "$input" in
            s) proj="system" ;;
            t) proj="technical" ;;
            w) proj="re-l" ;;
            e) proj="emporium" ;;
            l) proj="life" ;;
            r) proj="radiant" ;;
            y) proj="yuko" ;;
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

# --- FINANCE & AGENT PATHING ---
export FINANCE_DIR="$HOME/wiki_yuko/finance"
export LEDGER_FILE="$FINANCE_DIR/journal.ledger"  # The Master (includes others)
export KARMA_FILE="$FINANCE_DIR/karma.ledger"     # Active Agent data
export PERS_FILE="$FINANCE_DIR/personal.ledger"   # Personal budget data

# --- ALIASES (The Intelligence Layer) ---
alias bal='ledger bal'                            # Combined View
alias kbal='ledger -f $KARMA_FILE bal Agents'     # Agent Only View
alias sbal='ledger -f $KARMA_FILE bal Staging'    # Oracle/Staging View
alias tbal='ledger -f $PERS_FILE bal Assets'    # Personal Only View
alias ledg='vim $LEDGER_FILE'

# --- PERSONAL FUNCTIONS ---
# Usage: tadd 5.50 "Dr. Pepper"
tadd() {
  local date=$(date +%Y-%m-%d)
  {
    echo -e "\n$date * $2"
    echo -e "    Personal:Expenses:General      \$$1"
    echo -e "    Personal:Assets:Cash"
  } >> "$PERS_FILE"
  echo "Logged \$$1 to Personal Expenses."
}

# --- AGENT FUNCTIONS ---
# Usage: klog Trynn 50 "Quest Reward"
klog() {
  local date=$(date +%Y-%m-%d)
  {
    echo -e "\n$date * $3"
    echo -e "    Agents:$1:Karma               $2 KARMA"
    echo -e "    Agents:System:Income"
  } >> "$KARMA_FILE"
  echo "Logged $2 Karma for Agent $1."
}

# Usage: kbounty 100 "Manifold Market: Tournament Outcome"
kbounty() {
  local date=$(date +%Y-%m-%d)
  {
    echo -e "\n$date ! BOUNTY: $2"
    echo -e "    (Agents:Staging:Unassigned)    $1 KARMA"
    echo -e "    (Agents:System:Potential)"
  } >> "$KARMA_FILE"
  task add "$2" project:Bounties +KARMA:$1
  echo "Bounty staged ($1 KARMA) in Potential Space."
}

# Usage: kclaim Trynn 100 "Manifold Market: Tournament Outcome"
kclaim() {
  local date=$(date +%Y-%m-%d)
  {
    echo -e "\n$date * Claim: $3"
    echo -e "    Agents:$1:Karma               $2 KARMA"
    echo -e "    Agents:Staging:Unassigned    -$2 KARMA"
  } >> "$KARMA_FILE"
  # Mark the task as done in Taskwarrior
  task project:Bounties "/$3/" done
  echo "Karma attributed to $1; Bounty cleared."
}

