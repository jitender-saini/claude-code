# Claude Code Status Line

A rich terminal status line for [Claude Code](https://claude.ai/claude-code) that shows model info, context usage, tokens, git branch, cost, and more — right in your terminal.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/jitender-saini/claude-code/main/statusline/install.sh | bash
```

## What It Shows

| Indicator | Description |
|-----------|-------------|
| 🤖 Model | Current Claude model name |
| Context bar | Visual progress bar with color coding (green → yellow → red) |
| ↓↑ Tokens | Input/output token counts (auto-formats to K) |
| 🌿 Branch | Current git branch |
| 📝 Changes | Lines added/removed in session |
| 📁 Project | Project directory name |
| 💲 Cost | Session cost in USD |
| ⏱️ Duration | Total session duration |
| ⏳ API time | Cumulative API response time |

## Example

```
🤖 Opus 4 • ████░░░░░░░░ 35.2% • ↓ 42K ↑ 3K • 🌿 main • 📝 +12 -3 • 📁 my-project • $0.45 • ⏱️ 2m30s
```

## Manual Install

1. Copy `statusline-command.sh` to `~/.claude/`:
   ```bash
   cp statusline/statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. Add to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "command": "cat ~/.claude/statusline-command.sh"
     }
   }
   ```

3. Restart Claude Code.

## Alternative: jq Version

A `jq`-based variant is available at `statusline-command_jq.sh`. It uses a single `jq` call for JSON parsing instead of bash regex. Requires [jq](https://jqlang.github.io/jq/) to be installed.

## How It Works

Claude Code pipes JSON status data to the configured command via stdin. The script:

1. Reads the full JSON blob from stdin
2. Extracts fields using bash regex (`=~` with `BASH_REMATCH`) — no external dependencies
3. Formats each field with ANSI colors and icons
4. Joins all parts with a dot separator and prints to stdout

## Customization

Edit `~/.claude/statusline-command.sh` to:

- **Reorder sections**: Move items in the `parts+=()` array
- **Change colors**: Modify ANSI codes (e.g., `\033[33m` for yellow)
- **Remove sections**: Comment out or delete any `parts+=()` block
- **Change icons**: Replace emoji characters
- **Adjust thresholds**: Modify the context bar color breakpoints (currently 50% and 80%)
