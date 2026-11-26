#!/usr/bin/env bash
# fast-subagent — one bounded chat completion against the shared router's
# fast-subagent role, from any harness (Claude Code, Codex, OpenCode, Hermes…).
#
# Usage:  fast-subagent.sh [options] < prompt.txt
#   --model NAME      role alias to request (default: $FAST_SUBAGENT_MODEL, else "small")
#   --system TEXT     system prompt (default: a small-model extraction persona)
#   --prefix-file F   prepend shared prefix from F (JSON messages array or text/markdown)
#   --save-chain F    write full messages array + reply to F for subsequent prefix reuse
#   --session-id ID   send litellm_session_id / x-litellm-session-id for cache affinity
#   --max-tokens N    completion cap (default 1024)
#   --timeout SEC     per-request wall clock (default 180)
#   --release         send the voluntary lock-release header on this call
#   --raw             print the full JSON response instead of the text
#
# Endpoint discovery, first match wins (never a provider key, never a literal host):
#   LLM_ROUTER_URL + LLM_ROUTER_TOKEN_FILE (a file holding the bearer) — shared router
#   OPENAI_API_BASE_URL | LITELLM_LOCAL_BASE_URL + LITELLM_LOCAL_KEY | OPENAI_API_KEY — local proxy
# The router owns WHICH backend answers and the fallback order; this script
# only names the role. The answering model id is printed to stderr as
# `model=<id> fallbacks=<n>` so a caller can report which rung answered.
#
# Exit codes: 0 ok · 2 no endpoint or cloud session · 3 auth refused · 4 still busy after one
# Retry-After wait · 5 request/transport failure · 6 bad usage · 7 empty answer
# (the model spent --max-tokens on reasoning or finish_reason=length; raise it).
set -euo pipefail

model="${FAST_SUBAGENT_MODEL:-small}"
system='You are a fast, literal assistant. Do exactly what the instruction says. Do not explain, advise, or pad. Copy text verbatim; write UNKNOWN rather than guess.'
system_explicit=0
prefix_file=""
save_chain=""
session_id=""
max_tokens=1024
timeout=180
release=0
raw=0

need_arg() {
  if [ "$#" -lt 2 ]; then
    echo "fast-subagent: $1 requires an argument" >&2
    exit 6
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --model) need_arg "$@"; model="$2"; shift 2 ;;
    --system) need_arg "$@"; system="$2"; system_explicit=1; shift 2 ;;
    --prefix-file) need_arg "$@"; prefix_file="$2"; shift 2 ;;
    --save-chain) need_arg "$@"; save_chain="$2"; shift 2 ;;
    --session-id) need_arg "$@"; session_id="$2"; shift 2 ;;
    --max-tokens) need_arg "$@"; max_tokens="$2"; shift 2 ;;
    --timeout) need_arg "$@"; timeout="$2"; shift 2 ;;
    --release) release=1; shift ;;
    --raw) raw=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "fast-subagent: unknown option $1" >&2; exit 6 ;;
  esac
done

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  echo "fast-subagent: local-only, skipped: model router (cloud session)" >&2
  exit 2
fi

local_base="${OPENAI_API_BASE_URL:-${LITELLM_LOCAL_BASE_URL:-}}"
if [ -n "${LLM_ROUTER_URL:-}" ] && [ -r "${LLM_ROUTER_TOKEN_FILE:-/nonexistent}" ]; then
  base="${LLM_ROUTER_URL%/}"; key="$(cat "$LLM_ROUTER_TOKEN_FILE")"
elif [ -n "$local_base" ] && [ -n "${LITELLM_LOCAL_KEY:-${OPENAI_API_KEY:-}}" ]; then
  base="${local_base%/}"; key="${LITELLM_LOCAL_KEY:-$OPENAI_API_KEY}"
else
  echo "fast-subagent: no router endpoint in the environment (LLM_ROUTER_URL+LLM_ROUTER_TOKEN_FILE or OPENAI_API_BASE_URL|LITELLM_LOCAL_BASE_URL+LITELLM_LOCAL_KEY); do the step yourself and say so" >&2
  exit 2
fi
case "$base" in */v1) ;; *) base="$base/v1" ;; esac

prompt="$(cat)"
[ -n "$prompt" ] || { echo "fast-subagent: empty prompt on stdin" >&2; exit 6; }

hdr="$(mktemp)"; out="$(mktemp)"; msgs_file="$(mktemp)"; req_file="$(mktemp)"
trap 'rm -f "$hdr" "$out" "$msgs_file" "$req_file"' EXIT

if [ -n "$prefix_file" ]; then
  [ -r "$prefix_file" ] || { echo "fast-subagent: unreadable --prefix-file: $prefix_file" >&2; exit 6; }
  if jq -e 'type == "array"' "$prefix_file" >/dev/null 2>&1; then
    jq -e 'length > 0 and all(.[]; (type == "object") and (.role | type == "string") and (.content | type == "string"))' "$prefix_file" >/dev/null 2>&1 || {
      echo "fast-subagent: invalid message array in --prefix-file: $prefix_file" >&2
      exit 6
    }
    if [ "$system_explicit" = 1 ]; then
      echo "fast-subagent: --system cannot be combined with a JSON message array --prefix-file" >&2
      exit 6
    fi
    jq -cn --slurpfile pfx "$prefix_file" --arg p "$prompt" '$pfx[0] + [{role:"user",content:$p}]' > "$msgs_file"
  elif [ "$system_explicit" = 1 ]; then
    jq -cn --arg s "$system" --rawfile ctx "$prefix_file" --arg p "$prompt" \
      '[{role:"system",content:$s},{role:"user",content:$ctx},{role:"assistant",content:"Context loaded."},{role:"user",content:$p}]' > "$msgs_file"
  else
    jq -cn --rawfile s "$prefix_file" --arg p "$prompt" \
      '[{role:"system",content:$s},{role:"user",content:$p}]' > "$msgs_file"
  fi
else
  jq -cn --arg s "$system" --arg p "$prompt" '[{role:"system",content:$s},{role:"user",content:$p}]' > "$msgs_file"
fi

jq -cn --arg m "$model" --argjson n "$max_tokens" --slurpfile msgs "$msgs_file" --arg sid "$session_id" \
  '{model:$m, max_tokens:$n, temperature:0, messages:$msgs[0]} + (if $sid != "" then {litellm_session_id:$sid} else {} end)' > "$req_file"

extra=()
[ "$release" = 1 ] && extra+=(-H 'x-subagent-release: 1')
[ -n "$session_id" ] && extra+=(-H "x-litellm-session-id: $session_id")

req_bytes="$(wc -c < "$req_file" | tr -d ' ')"
if [ "$req_bytes" -lt 65536 ]; then
  payload_flag=(-d "$(cat "$req_file")")
else
  payload_flag=(--data-binary "@$req_file")
fi

call() {
  curl -sS --max-time "$timeout" -o "$out" -D "$hdr" -w '%{http_code}' \
    -H "Authorization: Bearer $key" -H 'content-type: application/json' "${extra[@]}" \
    "${payload_flag[@]}" "$base/chat/completions" 2>/dev/null || echo 000
}

code="$(call)"
if [ "$code" = 429 ]; then
  wait="$(awk 'tolower($1)=="retry-after:"{gsub(/\r/,"",$2);print $2}' "$hdr")"
  wait="${wait:-5}"; [ "$wait" -gt 60 ] 2>/dev/null && wait=60
  echo "fast-subagent: $model busy ($(jq -r '.error.message // .detail // "429"' "$out" 2>/dev/null | head -c 160)); retrying once in ${wait}s" >&2
  sleep "$wait"
  code="$(call)"
fi

case "$code" in
  200) ;;
  401|403) echo "fast-subagent: auth refused ($code) — key not valid for $model; do not retry with another credential" >&2; exit 3 ;;
  429) echo "fast-subagent: $model still busy after one wait — take another entry or do the step yourself, and say which" >&2; exit 4 ;;
  *) echo "fast-subagent: $model request failed (HTTP $code): $(head -c 300 "$out" 2>/dev/null)" >&2; exit 5 ;;
esac

hv() { awk -v k="$1:" 'tolower($1)==k{gsub(/\r/,"",$2);print $2}' "$hdr"; }
served="$(hv x-litellm-model-name)"; fell="$(hv x-litellm-attempted-fallbacks)"
echo "model=${served:-$(jq -r '.model // "?"' "$out")} fallbacks=${fell:-?}" >&2
text="$(jq -r '.choices[0].message.content // empty' "$out")"
if [ -n "$save_chain" ] && [ -n "$text" ]; then
  save_tmp="$(mktemp)"
  mkdir -p "$(dirname "$save_chain")"
  jq -cn --slurpfile msgs "$msgs_file" --arg a "$text" '$msgs[0] + [{role:"assistant",content:$a}]' > "$save_tmp"
  mv "$save_tmp" "$save_chain"
fi
if [ "$raw" = 1 ]; then cat "$out"; exit 0; fi
if [ -z "$text" ]; then
  echo "fast-subagent: $model returned no content (finish_reason=$(jq -r '.choices[0].finish_reason // "?"' "$out")) — raise --max-tokens or shorten the prompt" >&2
  exit 7
fi
printf '%s\n' "$text"
