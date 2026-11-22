#!/bin/bash
# write-script-guard.sh - PreToolUse hook to prevent unnecessary script file creation
#
# Two-stage guard:
#   Stage 1 (instant): Skip non-script files by extension/shebang
#   Stage 2 (for suspected scripts): Allow known directories, existing files,
#     then consult local MLX model for nuanced evaluation
#
# Exit codes: 0=allow, 2=deny

set -euo pipefail

# Read JSON input from stdin (fail-open if jq fails)
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
content=$(echo "$input" | jq -r '.tool_input.content // empty' 2>/dev/null) || exit 0

# If no file path, allow (fail-open)
if [[ -z "$file_path" ]]; then
    exit 0
fi

# --- Stage 1: Fast pattern check ---

# Extract file extension (lowercase, tr for macOS bash 3.x compatibility)
extension=$(echo "${file_path##*.}" | tr '[:upper:]' '[:lower:]')

# If NOT a script extension AND no shebang, allow immediately (most files exit here)
case "$extension" in
    sh|py|rb|pl|js|bash|zsh|fish) ;;  # fall through to stage 2
    *) [[ "$content" == "#!"* ]] || exit 0 ;;
esac

# --- Stage 2: Evaluate suspected scripts ---

# Allow files in known script directories
case "$file_path" in
    */scripts/*|*/hooks/*|*/.github/*|*/tests/*|*/test/*|*/plugins/*) exit 0 ;;
esac

# Expand ~ to $HOME for path normalization (Claude Code may pass ~ paths)
file_path="${file_path/#\~/$HOME}"

# Check if file already exists (editing existing scripts is fine)
if [[ -f "$file_path" ]]; then
    exit 0
fi

# Consult the small router capability for nuanced evaluation
judge_url="${GUARD_JUDGE_URL:-http://localhost:11434/v1/chat/completions}"
judge_down_closed=0
if [[ -n "${CI:-}" ]] || [[ "${GUARD_JUDGE_DOWN:-}" == "closed" ]]; then
    judge_down_closed=1
fi

# Return success only when a decision was received. Transport, HTTP, parse, and
# undecided responses are all treated as judge-down.
ask_judge() {
    local response decision_line

    response=$(curl -fsS --max-time 30 "$judge_url" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg fp "$file_path" \
            '{
                model: "small",
                chat_template_kwargs: {enable_thinking: false},
                messages: [{
                    role: "user",
                    content: ("You are a script-prevention guardrail. A file is being created at: " + $fp + "\n\nIs this a legitimate committed artifact (CI workflow, plugin hook, test fixture, build tool) or an unnecessary custom script?\n\nRespond with ONLY '\''allow'\'' or '\''deny'\'' followed by a brief reason.")
                }],
                max_tokens: 100,
                temperature: 0
            }')" 2>/dev/null) || return 1

    decision=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null) || return 1
    decision_line=$(printf '%s\n' "$decision" | head -1 | sed 's/^[[:space:]]*//')
    case "$decision_line" in
        [Dd][Ee][Nn][Yy]*) judge_decision=deny ;;
        [Aa][Ll][Ll][Oo][Ww]*) judge_decision=allow ;;
        *) return 1 ;;
    esac
    return 0
}

log_judge_down() {
    local outcome="$1" target log_dir timestamp
    target=$(printf '%s' "$file_path" | tr '\r\n\t' '   ' | cut -c1-80)
    log_dir="${CLAUDE_PLUGIN_DATA:-$HOME/.claude}"
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    mkdir -p "$log_dir" 2>/dev/null || return 0
    printf '%s guard=write-script-guard decision=%s path=%s\n' \
        "$timestamp" "$outcome" "$target" >> "$log_dir/content-guards.log" 2>/dev/null || true
}

if ! ask_judge; then
    if [[ "$judge_down_closed" -eq 1 ]]; then
        # Fail-closed environments get one retry before the judge is considered down.
        if ! ask_judge; then
            log_judge_down judge_down_block
            printf '%s\n' \
                'The script judge is unreachable and this environment fails closed. Retry, or put the file under an allowed path (scripts/, hooks/, .github/, tests/).' \
                'Actual exempt paths: scripts/, hooks/, .github/, tests/, test/, plugins/.' >&2
            exit 2
        fi
    else
        log_judge_down judge_down_allow
        exit 0
    fi
fi

# Check if response starts with "deny" (case-insensitive)
if [[ "$judge_decision" == "deny" ]]; then
    reason="${decision#[Dd][Ee][Nn][Yy]}"
    reason="${reason#"${reason%%[![:space:]]*}"}"
    jq -n --arg fp "$file_path" --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: ("BLOCKED: Script creation at \(.fp) was denied.\n\nReason: \(.reason)\n\nUse existing tools, CLIs, or native patterns instead of creating new scripts. If this script is a legitimate committed artifact, place it in scripts/, hooks/, .github/, or tests/ directories.")
        }
    }' >&2
    exit 2
fi

# The judge explicitly allowed the script.
exit 0
