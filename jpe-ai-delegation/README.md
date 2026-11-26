# jpe-ai-delegation

This plugin is specific to the maintainer's own setup and is not intended for general use.

## Skills

- **`/delegation-ladder`** - Apply the maintainer's executor ladder, eligibility rules, and verification steps
- **`/semaphore-converge`** - Ask the router's converge agent for a Semaphore preview, then run one confirmed template by id;
  no caller touches Semaphore directly

## Hooks

- **Spawn router and permission judge** - Apply the maintainer-specific policy documented in the delegation-ladder
  references; untagged spawns are classified on the on-host router's `small` alias and shell permission asks are judged
  on its `medium` alias, so neither utility call spends the Codex subscription
- **Codex eligibility** - When the metrics feed has no fresh Codex row, the hook reads the native `codex-quota`
  command instead (cached for four hours, failures for ten minutes) and skips Codex unless it exits 0 below the
  80-percent used threshold
- **No Claude rung** - No spawn runs on a Claude model: native custom agents take the executor ladder, and when no
  non-Claude executor answers the spawn is refused with `no non-Claude executor answered; nothing ran`; an
  `agent.spawn` hook denies tool-started and teammate subagent spawns
- **Sandbox executors** - Qwen (`opencode-qwen`) ranks first for public coding, ahead of ZCode, OpenCode Go and Cursor
- **Route telemetry** - Route events also go to the session's telemetry collector when one is configured

## Installation

```bash
claude plugins add jacobpevans-cc-plugins/jpe-ai-delegation
```

## Usage

```text
/delegation-ladder
```

Run `scripts/agent-route <kind>` from the plugin root to print the first
eligible executor. Add `scripts/` to `PATH` to invoke it as `agent-route`.
`AGENT_ROUTE_CODEX_QUOTA=available|exhausted` replaces the Codex quota check
for tests.

## License

MIT
