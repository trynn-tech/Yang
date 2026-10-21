# ==========================================
# YUKO MOBILE CONFIG (BASH)
# ==========================================

# --- NAV & BASICS ---
alias l='ls -lh'
alias ll='ls -la'
alias la='ls -lah'
alias cs="cd /data/data/com.termux/files/home/storage/shared/Download"
alias vwi='vim ~/wiki_yuko/index.md'
alias vd='vim -c "VimwikiMakeDiaryNote"'
alias t='task'
alias te='task edit'
alias tu='task append'
alias tf='task done'
alias td='task delete'
alias ts='task sync'
alias cx='task context none && clear && echo -e "\033[1;32mContext Cleared\033[0m"'
alias ctx='task context define tz' # tz for task zone
alias r='report'
alias ic='task add +inbox'
alias iv='task add +inbox +note'

alias ii='task rc.defaultwidth=100 rc.report.list.columns="id,entry.age,due.age,priority,project,tags,description" rc.report.list.labels="ID,Age,Due,Pri,Project,Tags,Description" rc.report.list.sort=entry+ +inbox list'
alias ir='task rc.defaultwidth=100 rc.report.next.columns="id,entry.age,due.age,priority,project,tags,description" rc.report.next.labels="ID,Age,Due,Pri,Project,Tags,Description" +inbox rc.report.next.sort="urgency+" limit:0 next'
alias review='task rc.defaultwidth=100 rc.report.list.columns="id,entry.age,due.age,priority,project,tags,description" rc.report.list.labels="ID,Age,Due,Pri,Project,Tags,Description" status:pending entry.after:2wago list'

# --- PROJECT ENGINES ---
projects=("s:system" "t:technical" "y:yuko" "w:re-l" "e:emporium" "r:radiant" "l:life")

# PROJECT CRUD ENGINE
_proj() {
    local p=$1 action=$2
    shift 2
    case $action in
        c) task add project:"$p" "$@" ;;
        r) task project:"$p" list ;;
        u) task "$1" modify "${@:2}" ;;
        d) task "$1" done ;;
        rm) task "$1" delete ;;
        *) task project:"$p" "$action" "$@" ;;
    esac
}

# CONTEXT SWITCH ENGINE
_ctx() {
    local p=$1
    task context define "$p" project:"$p" 2>/dev/null
    task context "$p"
    clear
    echo -e "\033[1;33mContext switched to: $p\033[0m"
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
# Resilient Queue Pipeline (Synced with Nix logic)
sort() {
    local taskBin="${TASKWARIOR_BIN:-task}"
    local -a skipped_ids=()

    while true; do
        local id=""
        local -a exclude_args=()
        for skip_id in "${skipped_ids[@]}"; do
            exclude_args+=( "id.not:${skip_id}" )
        done

        id="$("$taskBin" +inbox +READY sort:priority- "${exclude_args[@]}" _ids 2>/dev/null | head -n 1)"
        id="${id//[[:space:]]/}"

        clear
        echo -e "\033[1;33m==== CONTROLLER ARRAY DIAGNOSTICS ====\033[0m"
        echo "Skipped IDs List Array Count  : ${#skipped_ids[@]}"
        echo "Skipped IDs Array Elements     : ${skipped_ids[@]}"
        echo "Generated Individual Tokens    : ${exclude_args[@]}"
        echo -e "\033[1;33m======================================\033[0m\n"

        if [[ -z "${id}" ]]; then
            echo -e "\033[1;32m✅ Inbox triage complete for this session!\033[0m"
            break
        fi

        echo -e "\033[1;35m--- Next Inbox Item: ${id} ---\033[0m"
        "$taskBin" "${id}" info
        echo -e "\n\033[1;36mPRIORITY:\033[0m [H] High | [M] Medium | [L] Low | [Enter] Advance/Skip | [Q] Quit"
        echo -n "🚀 Select option (h/m/l/Enter/q): "

        local input=""
        read -r input < /dev/tty
        local action="${input^^}"

        if [[ "${action}" == "Q" ]]; then
            break
        fi

        case "${action}" in
            H|M|L)
                "$taskBin" "${id}" modify priority:"${action}" >/dev/null 2>&1
                skipped_ids+=( "${id}" )
                ;;
            *)
                skipped_ids+=( "${id}" )
                ;;
        esac
        sleep 0.1
    done
}

# Project Triage Flow
it() {
    local id=$(task +inbox +READY sort:priority- _ids | awk -F',' '{print $1}')
    if [ -z "$id" ]; then
        echo -e "\033[1;32m✅ Inbox empty\033[0m"
    else
        echo -e "\n\033[1;35m--- Next Inbox Item ---\033[0m"
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
report() {
    echo -e "\n\033[1;35m--- [ PERFORMANCE REPORT ] ---\033[0m"
    local done=$(task end:today status:completed count)
    local pending=$(task status:pending count)
    echo -e "Completed Today: \033[1;38;5;141m$done\033[0m | Pending: \033[1;38;5;183m$pending\033[0m"
    echo -e "\n\033[1;38;5;177mCurrently Clocked In:\033[0m"
    
    # Custom two-row active task processor (Row 1: Metadata, Row 2: Description)
    local active_export
    active_export=$(task +ACTIVE export 2>/dev/null)
    
    if [[ -z "$active_export" || "$active_export" == "[]" ]]; then
        echo "  (No tasks currently started)"
    else
        echo "$active_export" | jq -r '.[] | "\(.id)|\(.entry)|\(.due // "None")|\(.priority // "None")|\(.project // "none")|\(.description)"' | while IFS='|' read -r id entry due pri proj desc; do
            echo -e "  \033[1;38;5;141m[#$id]\033[0m Pri: \033[1;38;5;213m$pri\033[0m | Proj: \033[1;38;5;183m$proj\033[0m | Due: $due"
            echo -e "    ↳ \033[1;38;5;225m$desc\033[0m"
            echo ""
        done
    fi
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
export LEDGER_FILE="$FINANCE_DIR/journal.ledger"
export KARMA_FILE="$FINANCE_DIR/karma.ledger"
export PERS_FILE="$FINANCE_DIR/personal.ledger"

# --- ALIASES (The Intelligence Layer) ---
alias bal='ledger bal'
alias kbal='ledger -f $KARMA_FILE bal Agents'
alias sbal='ledger -f $KARMA_FILE bal Staging'
alias tbal='ledger -f $PERS_FILE bal Assets'
alias ledg='vim $LEDGER_FILE'

# --- PERSONAL FUNCTIONS ---
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
klog() {
    local date=$(date +%Y-%m-%d)
    {
        echo -e "\n$date * $3"
        echo -e "    Agents:$1:Karma               $2 KARMA"
        echo -e "    Agents:System:Income"
    } >> "$KARMA_FILE"
    echo "Logged $2 Karma for Agent $1."
}

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

kclaim() {
    local date=$(date +%Y-%m-%d)
    {
        echo -e "\n$date * Claim: $3"
        echo -e "    Agents:$1:Karma               $2 KARMA"
        echo -e "    Agents:Staging:Unassigned    -$2 KARMA"
    } >> "$KARMA_FILE"
    task project:Bounties "/$3/" done
    echo "Karma attributed to $1; Bounty cleared."
}

# === BEGIN AUTOMATIC SSH KEYCHAIN CONFIGURATION ===

# Protocol: Full Purge (Kills multiplexers, clears memory, kills agent daemons)
ssh-teardown() {
    echo "[*] Triggering full secure teardown..."
    
    # 1. Wipe keys from memory
    if command -v ssh-add &>/dev/null; then
        ssh-add -D &>/dev/null || true
    fi
    
    # 2. Kill Keychain/ssh-agent daemons
    if command -v keychain &>/dev/null; then
        keychain -k all &>/dev/null || true
    fi

    # 3. Gracefully kill all active tmux sessions
    if command -v tmux &>/dev/null; then
        tmux kill-server 2>/dev/null || true
    fi

    # 4. Clean up any leftover background tracking processes
    pkill -f "ssh-teardown-timer" 2>/dev/null || true

    echo "[+] Environment secure. Sockets wiped and multiplexers terminated."
}

# Protocol: Initialize (Spins up agent, prompts for passphrase, schedules 24h wipe)
ssh-init() {
    if ! command -v keychain &> /dev/null; then
        echo "[!] Error: keychain is not installed."
        return 1
    fi

    echo "[*] Checking for existing SSH agent..."
    eval $(keychain --eval --agents ssh --noask id_ed25519)
    
    # Prompt for passphrase if key isn't decrypted yet
    if ! ssh-add -l &>/dev/null; then
        echo "[!] Key not loaded. Prompting for passphrase..."
        keychain id_ed25519
        eval $(keychain --eval --agents ssh id_ed25519)
    else
        echo "[+] Active SSH agent found and key is already loaded!"
    fi

    # Schedule the 24-hour Auto-Teardown
    echo "[*] Scheduling secure environment teardown in 24 hours..."
    
    if command -v at &>/dev/null && { command -v sv &>/dev/null || [ ! -d "/data/data/com.termux" ]; }; then
        # On native Linux / systems with reliable atd daemons
        echo "bash -c 'source $HOME/.bashrc && ssh-teardown'" | at now + 24 hours 2>/dev/null
        echo "[+] Scheduled via system 'at' queue."
    else
        # Termux/Android fallback tracker: Runs decoupled to handle OS sleep states
        pkill -f "ssh-teardown-timer" 2>/dev/null || true
        (
            # 86400 seconds = 24 hours
            sleep 86400
            source "$HOME/.bashrc"
            ssh-teardown
        ) >/dev/null 2>&1 &
        echo "[+] Background sleep daemon spawned (PID: $!)."
    fi
}
# === END AUTOMATIC SSH KEYCHAIN CONFIGURATION ===
