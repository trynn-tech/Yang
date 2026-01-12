# ==========================================
# YUKO MOBILE CONFIG (BASH)
# ==========================================

# --- NAV & BASICS ---
alias l='ls'
alias cs="cd /data/data/com.termux/files/home/storage/shared/Download"
alias vwi='vim ~/yang_wiki/index.md'
alias addmd="find . -type f -exec mv '{}' '{}'.pdf \;"

# --- PROJECT BRAID ---
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
alias ip='task modify'
alias review='task status:pending age.gt:2w list'

# TRIAGE LOOP
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

# --- FINANCE & AGENT PATHING ---
export FINANCE_DIR="$HOME/yang_wiki/finance"
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

