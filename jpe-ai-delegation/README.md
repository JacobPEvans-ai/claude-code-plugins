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
- **Retired agent types** - A type named in the operator's `~/.config/ai-delegation/retired.json` is refused with
  the replacement command its entry names, before any definition is read or executor is called; the plugin ships
  no map, so a missing or malformed file retires nothing
- **Sandbox executors** - Qwen (`opencode-qwen`) ranks first for public coding, ahead of ZCode, OpenCode Go and Cursor
- **Route telemetry** - Route events also go to the session's telemetry collector when one is configured

## Headless harness

- **Alias and child environment** - Harness rows accept only non-Claude, non-Anthropic aliases. Before launch, the hook
  builds a child environment and pins every model selector to the row alias. Anthropic API-key and OAuth credential
  variables are blank, the auth token is set to a local proxy placeholder, and Anthropic base URLs are rejected. The
  child tool allowlist omits `Agent` and `Task`.
- **Result checks** - After a successful run, the hook checks `modelUsage` for forbidden model names. A match is logged
  as a `violation` and blocks that row for the rest of the session. Raw chat-template tokens and `<tool_call>` or
  `<function_call>` tags are rejected; failed answers fall through without logging their text.
- **Model Context Protocol (MCP) agents** - Custom agents that declare `mcpServers` or `mcp__` tools run only on harness
  rows. The hook accepts stdio servers with absolute command paths and string arguments and environment values, passes
  their configuration with `--strict-mcp-config`, and allows only MCP tool patterns from the agent's `tools` list.
  Invalid MCP definitions or MCP tool declarations without server configuration are refused.
- **Network work** - Work that needs network access runs only on harness rows.
- **Public code eligibility** - Code for a verified public repository reaches the sandbox rows only after a
  secret-material scan and a `sensitivity-homelab` decision from the on-host router. A private verdict keeps it off
  sandbox rows; if the decision call fails, the existing credential word list decides. Code for a private or
  unverified repository can run on the harness rows as well as Codex.
- **Known limit** - `modelUsage` reports the alias requested by the child, so the router's own fallback chain must be
  kept free of Anthropic models.

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
