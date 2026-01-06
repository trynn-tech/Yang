alias addmd="find . -type f -exec mv '{}' '{}'.pdf \;"
alias cs="cd /data/data/com.termux/files/home/storage/shared/Download"
alias vwi='vim ~/yang_wiki/index.md'
alias l='ls'

# Define your keys and project names here
# Format: "key:ProjectName"
projects=("s:System" "t:Taskwiki" "w:Work" "r:Radiant-Pact")

for entry in "${projects[@]}"; do
    key="${entry%%:*}"
    name="${entry#*:}"
    alias "${key}c"="_proj $name c"
    alias "${key}r"="_proj $name r"
    alias "${key}u"="_proj $name u"
    alias "${key}d"="_proj $name d"
done

# The Master Project Function
# Usage: _proj [project_name] [action] [args...]
_proj() {
    local p=$1
    local action=$2
    shift 2
    case $action in
        c) task add project:"$p" "$@" ;;  # Create
        r) task project:"$p" list ;;      # Read
        u) task "$1" modify "$@:2" ;;     # Update (requires ID)
        d) task "$1" delete ;;            # Delete (requires ID)
        *) task project:"$p" "$action" "$@" ;; # Fallback for other commands
    esac
}

# 1. The Context Switcher Function
# Usage: _ctx [ProjectName]
_ctx() {
    local p=$1
    # Define it if it doesn't exist, then switch
    task context define "$p" project:"$p" 2>/dev/null
    task context "$p"
    clear
    echo -e "\033[1;33mContext switched to: $p\033[0m"
    report
}

# 2. Update your Project Loop
# This adds the 'x' (eXchange) command for every project key
projects=("s:SystemRepair" "t:Taskwiki" "w:Work" "h:Home")

for entry in "${projects[@]}"; do
    key="${entry%%:*}"
    name="${entry#*:}"

    # CRUD
    alias "${key}c"="_proj $name c"
    alias "${key}r"="_proj $name r"

    # THE SWITCHER: e.g., 'sx' switches to SystemRepair
    alias "${key}x"="_ctx $name"
done

# Quick Capture to Inbox (no project assigned)
alias ic='task add +inbox'

# View the Inbox
alias ir='task +inbox list'

# Process the oldest task in the Inbox
it() {
    # Get the ID of the oldest task in the inbox
    local id=$(task +inbox _ids | awk -F',' '{print $1}')
    
    if [ -z "$id" ]; then
        echo "✅ Inbox is empty!"
    else
        task "$id" info
        echo -n "🚀 Move to which project? (e.g., SystemRepair): "
        read proj
        # Moves project and strips the inbox tag in one go
        task "$id" modify project:"$proj" -inbox
    fi
}

# Tasks older than 2 weeks that haven't been touched
alias review='task status:pending age.gt:2w list'

# report: High-speed status check
report() {
    echo -e "\033[1;35m--- [ PERFORMANCE REPORT ] ---\033[0m"

    # Show the Progress Bar
    get_task_progress

    # Show Active Context
    local current_ctx=$(task _get rc.context)
    if [ -z "$current_ctx" ]; then
        echo -e "Context: \033[1;30mNone (Global View)\033[0m"
    else
        echo -e "Context: \033[1;33m$current_ctx\033[0m"
        echo -e "Tasks in this project: $(task status:pending count)"
    fi

    # Show any 'Started' tasks (The +ACTIVE ones)
    echo -e "\n\033[1;34mCurrently Clocked In:\033[0m"
    task +ACTIVE list || echo "  (No tasks currently started)"
}

# tll: Task List Longitudinal (The Project Health Map)
alias tll='echo -e "\033[1;34m--- [ PROJECT PROGRESS ] ---\033[0m"; task summary; echo -e "\n\033[1;35m--- [ PROJECT GAPS ] ---\033[0m"; task gprojects'

tlo() {
    clear
    echo -e "\033[1;35m==========================================\033[0m"
    echo -e "\033[1;35m          🏁 THE DAILY RECAP 🏁           \033[0m"
    echo -e "\033[1;35m==========================================\033[0m"

    # 1. Accomplishments
    echo -e "\n\033[1;32m🏆 TASKS COMPLETED TODAY:\033[0m"
    task end:today status:completed export | jq -r '.[].description' | sed 's/^/  [✓] /'
    
    # 2. Tomorrow's Top 3
    echo -e "\n\033[1;36m🚀 TOMORROW'S LAUNCHPAD:\033[0m"
    task +READY +PENDING limit:3

    # 3. Internal Sync
    echo -e "\n\033[1;34m🔄 SYNCING TASK DATABASE...\033[0m"
    task sync

    echo -e "\n\033[1;35m==========================================\033[0m"
    echo -e "   Recap Complete. Ready for manual Git push."
    echo -e "\033[1;35m==========================================\033[0m"
}

# Function to generate the progress bar
get_task_progress() {
    # Get counts for today
    local done=$(task end:today status:completed count)
    local deleted=$(task end:today status:deleted count)
    local total=$((done + deleted))

    # Avoid division by zero
    if [ "$total" -eq 0 ]; then
        echo -e "\033[1;30m[----------] 0%\033[0m"
        return
    fi

    # Calculate percentage
    local percent=$((done * 100 / total))
    local filled=$((percent / 10))
    local empty=$((10 - filled))

    # Build the bar string
    local bar="\033[1;32m"
    for ((i=0; i<filled; i++)); do bar+="="; done
    bar+="\033[1;30m"
    for ((i=0; i<empty; i++)); do bar+="-"; done

    echo -e "[$bar\033[1;30m] $percent%"
}
