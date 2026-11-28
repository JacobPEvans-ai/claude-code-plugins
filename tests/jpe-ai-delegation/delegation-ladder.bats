#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SKILL="$REPO_ROOT/jpe-ai-delegation/skills/delegation-ladder/SKILL.md"
  LADDER="$REPO_ROOT/jpe-ai-delegation/skills/delegation-ladder/ladder.json"
}

@test "ladder kinds match the delegation-ladder table" {
  # The skill lists each kind and leaves the order of executors to the hook; the next test pins the order in the data.
  markdown_kinds="$(awk -F '|' '/^\| `[^`]+` \|/ { kind=$2; gsub(/[ `]/, "", kind); print kind }' "$SKILL" | sort)"
  data_kinds="$(jq -r '.kinds | keys[]' "$LADDER" | sort)"
  [ -n "$markdown_kinds" ]
  [ "$markdown_kinds" = "$data_kinds" ]
}

@test "ladder contains the exact binding order, eligibility gates and no prohibited models" {
  [ "$(jq -r '.kinds | keys | sort | join("|")' "$LADDER")" = 'code|other|private' ]
  [ "$(jq -r '.kinds.code.rungs | map(.name) | join("|")' "$LADDER")" = 'Qwen sandbox|zcode-job sandbox|Codex|Z.ai GLM|OpenCode Go' ]
  [ "$(jq -r '.kinds.private.rungs | map(.name) | join("|")' "$LADDER")" = 'Codex' ]
  [ "$(jq -r '.kinds.other.rungs | map(.name) | join("|")' "$LADDER")" = 'Codex|Z.ai GLM|OpenCode Go' ]
  run grep -iE 'sonnet|opus|fable|litellm|small|terra' "$LADDER"
  [ "$status" -eq 1 ]
}

@test "skill points at the routing statement and keeps only procedure" {
  for rule in 'codex-quota' "AGENTS.md, 'Delegation routing'" 'not restate it' 'more than 5% left' '[class: bulk-complex]' 'obvious, definitely non-sensitive' 'public repos' 'Leak-scan' 'Never auto-merge' 'second-opinion reviewer' 'does not read quota'; do
    run grep -F "$rule" "$SKILL"
    [ "$status" -eq 0 ]
  done
  run grep -E 'first rung that qualifies|equal first choices|Qwen first|spend every' "$SKILL"
  [ "$status" -eq 1 ]
}

@test "skill and reference no longer describe bypasses or retired routes" {
  run grep -iE 'Luna only|Never Terra above|ai-untrusted-ok|classified-safe|payload classification|Terra `(medium|high)`|GLM runs only inside|Explicit model choices.*pass through|isolated spawns go to Haiku|text-only router lanes|runs Codex and Haiku only' "$SKILL" "$REPO_ROOT/jpe-ai-delegation/skills/delegation-ladder/references/estate-routing.md"
  [ "$status" -eq 1 ]
}
