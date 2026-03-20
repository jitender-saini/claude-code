#!/bin/bash
set -euo pipefail

# Claude Code Status Line — Installer
# Installs the statusline-command.sh script and configures Claude Code settings.

SCRIPT_URL="https://raw.githubusercontent.com/jitender-saini/claude-code/main/statusline/statusline-command.sh"
CLAUDE_DIR="$HOME/.claude"
SCRIPT_PATH="$CLAUDE_DIR/statusline-command.sh"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"
STATUSLINE_CMD="$HOME/.claude/statusline-command.sh"

info()  { printf '  \033[34m→\033[0m %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m⚠\033[0m %s\n' "$*"; }
err()   { printf '  \033[31m✗\033[0m %s\n' "$*"; }

echo ""
echo "  Claude Code Status Line — Installer"
echo "  ────────────────────────────────────"
echo ""

# ── Step 1: Ensure ~/.claude/ exists ────────────────────────────────────────
info "Ensuring $CLAUDE_DIR exists..."
mkdir -p "$CLAUDE_DIR"
ok "Directory ready: $CLAUDE_DIR"

# ── Step 2: Download statusline-command.sh ──────────────────────────────────
info "Downloading statusline-command.sh..."
downloaded=false

if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"; then
        downloaded=true
    fi
fi

if [ "$downloaded" = false ] && command -v wget >/dev/null 2>&1; then
    if wget -qO "$SCRIPT_PATH" "$SCRIPT_URL"; then
        downloaded=true
    fi
fi

if [ "$downloaded" = false ]; then
    err "Failed to download statusline-command.sh (tried curl and wget)"
    err "Please check your internet connection and try again."
    exit 1
fi

# Verify the download is not empty / not an error page
if [ ! -s "$SCRIPT_PATH" ]; then
    err "Downloaded file is empty — check that the URL is reachable:"
    err "  $SCRIPT_URL"
    exit 1
fi

chmod +x "$SCRIPT_PATH"
ok "Installed: $SCRIPT_PATH"

# ── Step 3: Configure Claude Code settings.json ────────────────────────────
info "Configuring $SETTINGS_PATH..."

STATUSLINE_VALUE="$STATUSLINE_CMD"

# ── Primary: Python-based JSON merge ────────────────────────────────────────
configure_with_python() {
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        return 1
    fi

    "$python_cmd" - "$SETTINGS_PATH" "$STATUSLINE_VALUE" <<'PYEOF'
import json, sys, os, shutil

settings_path = sys.argv[1]
statusline_value = sys.argv[2]

# Load existing settings or start fresh
settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, "r") as f:
            content = f.read().strip()
            if content:
                settings = json.loads(content)
    except (json.JSONDecodeError, ValueError):
        # Backup broken file
        bak = settings_path + ".bak"
        shutil.copy2(settings_path, bak)
        print(f"  \033[33m⚠\033[0m Backed up malformed settings to {bak}")
        settings = {}

# Merge statusLine key
settings["statusLine"] = {"type": "command", "command": statusline_value}

# Write atomically
tmp = settings_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)
PYEOF
}

# ── Fallback: Pure bash ─────────────────────────────────────────────────────
configure_with_bash() {
    local new_block
    new_block=$(printf '  "statusLine": {\n    "type": "command",\n    "command": "%s"\n  }' "$STATUSLINE_VALUE")

    if [ ! -f "$SETTINGS_PATH" ]; then
        # No file — write minimal config
        printf '{\n%s\n}\n' "$new_block" > "$SETTINGS_PATH"
        return 0
    fi

    local content
    content=$(cat "$SETTINGS_PATH")

    # Check if file looks like valid JSON (starts with { and ends with })
    local trimmed
    trimmed=$(echo "$content" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [[ ! "$trimmed" =~ ^\{ ]] || [[ ! "$trimmed" =~ \}$ ]]; then
        warn "Settings file doesn't look like valid JSON — backing up"
        cp "$SETTINGS_PATH" "${SETTINGS_PATH}.bak"
        printf '{\n%s\n}\n' "$new_block" > "$SETTINGS_PATH"
        return 0
    fi

    # Remove existing statusLine block using brace counting
    local in_statusline=false
    local brace_depth=0
    local result=""
    local prev_line=""
    local skip_comma=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$in_statusline" = true ]; then
            # Count braces in the line
            local opens="${line//[^\{]/}"
            local closes="${line//[^\}]/}"
            brace_depth=$(( brace_depth + ${#opens} - ${#closes} ))
            if [ "$brace_depth" -le 0 ]; then
                in_statusline=false
                skip_comma=true
            fi
            continue
        fi

        # Detect statusLine key
        if [[ "$line" =~ \"statusLine\" ]]; then
            in_statusline=true
            local opens="${line//[^\{]/}"
            local closes="${line//[^\}]/}"
            brace_depth=$(( ${#opens} - ${#closes} ))
            # Remove trailing comma from previous line if needed
            if [ -n "$result" ]; then
                result=$(printf '%s' "$result" | sed '$ s/,[[:space:]]*$//')
            fi
            if [ "$brace_depth" -le 0 ]; then
                in_statusline=false
                skip_comma=true
            fi
            continue
        fi

        if [ "$skip_comma" = true ]; then
            skip_comma=false
            # Skip lines that are just commas
            if [[ "$line" =~ ^[[:space:]]*,?[[:space:]]*$ ]]; then
                continue
            fi
        fi

        if [ -z "$result" ]; then
            result="$line"
        else
            result="$result
$line"
        fi
    done <<< "$content"

    # Insert new statusLine block before the final closing brace
    # Find the last } and insert before it
    local before_end
    before_end=$(printf '%s' "$result" | sed '$ d')
    local last_line
    last_line=$(printf '%s' "$result" | tail -1)

    # Check if there's content before the closing brace that needs a comma
    local needs_comma=false
    local trimmed_before
    trimmed_before=$(printf '%s' "$before_end" | sed '/^[[:space:]]*$/d' | tail -1)
    if [ -n "$trimmed_before" ] && [[ ! "$trimmed_before" =~ ,[[:space:]]*$ ]] && [[ ! "$trimmed_before" =~ ^\{ ]]; then
        needs_comma=true
    fi

    if [ "$needs_comma" = true ]; then
        printf '%s,\n%s\n%s\n' "$before_end" "$new_block" "$last_line" > "$SETTINGS_PATH"
    else
        printf '%s\n%s\n%s\n' "$before_end" "$new_block" "$last_line" > "$SETTINGS_PATH"
    fi
}

# Try Python first, fall back to bash
if configure_with_python; then
    ok "Settings updated (via Python)"
elif configure_with_bash; then
    ok "Settings updated (via bash fallback)"
else
    err "Failed to update settings"
    exit 1
fi

echo ""
ok "Installation complete!"
echo ""
info "Restart Claude Code to see the status line."
echo ""
