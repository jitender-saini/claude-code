#!/bin/bash
set -euo pipefail

input=$(cat)

# Single jq call — parse all fields at once
IFS=$'\t' read -r model used_pct input_tokens output_tokens cost duration_ms \
    lines_added lines_removed api_duration_ms cwd < <(
    echo "$input" | jq -r '[
        .model.display_name,
        .context_window.used_percentage,
        .context_window.current_usage.input_tokens,
        .context_window.current_usage.output_tokens,
        .cost.total_cost_usd,
        .cost.total_duration_ms,
        .cost.total_lines_added,
        .cost.total_lines_removed,
        .cost.total_api_duration_ms,
        (.workspace.project_dir // .workspace.current_dir // .cwd)
    ] | map(. // "") | @tsv'
) || true

# Extract project name from path
project=""
if [ -n "$cwd" ]; then
    project=$(basename "$cwd")
fi

# Get git branch (works with worktrees, submodules, and bare repos)
branch=""
if [ -n "$cwd" ]; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
fi

format_duration() {
    local ms=$1
    local sec=$(( ms / 1000 ))
    local m=$(( sec / 60 ))
    local s=$(( sec % 60 ))
    if [ "$m" -gt 0 ]; then
        printf '%dm%02ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

format_tokens() {
    local n=$1
    if [ "$n" -ge 1000 ] 2>/dev/null; then
        printf '%sK' "$(( n / 1000 ))"
    else
        printf '%s' "$n"
    fi
}

parts=()

# 1. Model name with robot icon
if [ -n "$model" ]; then
    parts+=("$(printf '\033[33m🤖  %s\033[0m' "$model")")
fi

# 2. Progress bar + Percentage (with warning icon when high)
if [ -n "$used_pct" ]; then
    used_int=${used_pct%.*}
    bar_width=12
    filled=$(( used_int * bar_width / 100 ))
    [ "$filled" -gt "$bar_width" ] 2>/dev/null && filled=$bar_width
    [ "$filled" -lt 0 ] 2>/dev/null && filled=0
    empty=$(( bar_width - filled ))

    if [ "$used_int" -ge 80 ] 2>/dev/null; then
        color='\033[31m'
        ctx_icon="⚠️ "
    elif [ "$used_int" -ge 50 ] 2>/dev/null; then
        color='\033[33m'
        ctx_icon=""
    else
        color='\033[32m'
        ctx_icon=""
    fi

    full_bar="████████████"
    empty_bar="░░░░░░░░░░░░"
    bar="${full_bar:0:filled}${empty_bar:0:empty}"

    parts+=("$(printf "${color}${ctx_icon}%s %s%%\033[0m" "$bar" "$used_pct")")
fi

# 3. Tokens
if [ -n "$input_tokens" ]; then
    in_display=$(format_tokens "$input_tokens")
    out_display=""
    if [ -n "$output_tokens" ]; then
        out_display=$(format_tokens "$output_tokens")
    fi
    if [ -n "$out_display" ]; then
        parts+=("$(printf '\033[36m↓ %s ↑ %s\033[0m' "$in_display" "$out_display")")
    else
        parts+=("$(printf '\033[36m↓ %s\033[0m' "$in_display")")
    fi
fi

# 4. Git branch with branch icon
if [ -n "$branch" ]; then
    parts+=("$(printf '\033[35m🌿  %s\033[0m' "$branch")")
fi

# 5. Lines changed
if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
    added="${lines_added:-0}"
    removed="${lines_removed:-0}"
    if [ "$added" -gt 0 ] 2>/dev/null || [ "$removed" -gt 0 ] 2>/dev/null; then
        parts+=("$(printf '📝  \033[32m+%s\033[0m \033[31m-%s\033[0m' "$added" "$removed")")
    fi
fi

# 6. Project name with folder icon
if [ -n "$project" ]; then
    parts+=("$(printf '\033[34m📁  %s\033[0m' "$project")")
fi

# 7. Session cost (rounded to 2 decimal places)
if [ -n "$cost" ]; then
    cost_fmt=$(printf '%.2f' "$cost")
    parts+=("$(printf '\033[32m$%s\033[0m' "$cost_fmt")")
fi

# 8. Session duration with clock icon
if [ -n "$duration_ms" ] && [ "$duration_ms" -gt 0 ] 2>/dev/null; then
    parts+=("$(printf '\033[37m⏱️  %s\033[0m' "$(format_duration "$duration_ms")")")
fi

# 9. API response time
if [ -n "$api_duration_ms" ] && [ "$api_duration_ms" -gt 0 ] 2>/dev/null; then
    parts+=("$(printf '\033[36m⏳ %s\033[0m' "$(format_duration "$api_duration_ms")")")
fi

separator="$(printf '\033[2m \xe2\x80\xa2 \033[0m')"

if [ ${#parts[@]} -gt 0 ]; then
    printf '%b' "${parts[0]}"
    for part in "${parts[@]:1}"; do
        printf '%b%b' "$separator" "$part"
    done
    printf '\n'
fi