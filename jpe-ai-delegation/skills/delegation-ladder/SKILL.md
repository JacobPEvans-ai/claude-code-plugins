---
name: delegation-ladder
description: "Describes how the maintainer's delegation hook places every spawn: task tags, route lines, refusals and verification rules. Use when tagging, sending or checking delegated work on the maintainer's own setup."
---

# Delegation ladder

The routing statement is AGENTS.md, 'Delegation routing', in the shared instructions repository. This skill does
not restate it. The hook places every spawn. The sections below say what the hook does, how to tag a task and how
to check a result. Shared doctrine: `prompt://dryvist/auto-ai-agent/model-delegation`.

- Codex qualifies while `codex-quota` exits 0 (more than 5% left).
- Complicated bulk and mandatory auth, secrets, router, memory and cluster topics name `[class: bulk-complex]`.
- A public sandbox takes only obvious, definitely non-sensitive coding in public repos. Its output is a ready PR.
  Leak-scan it before merge. Never auto-merge it.
- Antigravity (`agy`) stays a second-opinion reviewer, never an executor.

The hook ranks the eligible executors at call time, as described below. The `agent-route` helper does not read quota:
it reports a route from the hook's ladder data.

| Kind | Sandbox eligibility | Use |
| --- | --- | --- |
| `code` | Public coding tasks | Implementation |
| `private` | Ineligible | Private tasks |
| `other` | Ineligible | Reads, triage, summaries, review and planning |

## Dispatch and completion

The lead classifies the full payload, including attachments, diffs, logs and
conversation context, before dispatch. Use placeholders in work about sensitive
systems. The hook screens inline payloads locally before calling any classifier
or executor; it cannot inspect attachments or files that workers might read.
The lead must keep prohibited content out of executor-accessible context.

Codex routing follows AGENTS.md, 'Delegation routing' in the shared
instructions repository. Plan, design and architecture review use the `plan` or `deep` class and a read-only sandbox,
as do `Explore` and `Plan` agents. Explicit class tags select these routes;
mandatory bulk-complex topics override model selection while preserving an
explicit `plan` or `deep` read-only sandbox. Explicit models, named agents and
worktree isolation cannot bypass the ladder. Isolated Codex tasks get a
detached worktree, whose path is returned for review. Custom-agent
instructions are preserved; namespaced plugin agents resolve from the local
installed-plugin registry. Missing definitions stop dispatch. An agent type the
operator retired stops dispatch before any definition is read or executor is
called, with the replacement command its entry names in
`~/.config/ai-delegation/retired.json` (a JSON object from type to command,
read once per session; malformed entries are dropped and named in the log);
the plugin ships no map, so a missing or unreadable file retires nothing.

The hook places each task in this order and logs one JSON `route` line per
decision to `~/.claude/ai-delegation.log`:

1. Eligibility. On-host local aliases and Codex may see any task. Qwen
   (`zcode-job --tool opencode-qwen`), ZCode,
   OpenCode Go (`zcode-job --tool opencode`) and Cursor
   (`zcode-job --tool cursor-agent`) see only non-sensitive `[task: code]` work
   in a verified public repository; their dispatcher refuses private ones.
2. Local. A generic, non-isolated, non-code spawn marked `[class: text]` goes
   to the on-host `small` alias, or `local-only` when the prompt is larger.
   A generic spawn without a recognized class tag or `[task: code]` is classified
   once on the on-host `small` alias: `text` takes this rung, `code` makes the
   sandboxes eligible, and `other` changes nothing; recognized tags override
   classification, and a failed classification is `other`.
   A recognized explicit class tag other than `text` is never classified and never takes this rung.
   Put all of the task's text in the prompt; the local model has no tools. The token estimate (characters / 3.5 plus 2048 output) must fit in
   60% of the alias's context window from the router's `/model/info`. An empty
   answer, a length cut-off, an error or a timeout falls through.
3. Subscriptions. Quota comes from one instant query to the metrics store at
   `AGENT_QUOTA_QUERY_URL` for the `agent_quota_used_percent`,
   `agent_quota_window_seconds` and `agent_quota_reset_timestamp_seconds`
   series, grouped by `executor` and `window`. The plugin ships no default:
   unset means every quota is unknown and no request is made. When the URL
   is https and `AGENT_QUOTA_TOKEN_FILE` names a file holding one token (no
   whitespace or control characters once trimmed), the request carries
   `Authorization: Bearer` with it, read at call time and never logged;
   otherwise it carries no header. The route admits only the exact selector
   string. The hook reads it once per session with a 3-second timeout, which
   covers the token read, and refreshes it in the
   background every 10 minutes. An unreachable store, a timeout, a non-OK
   status (including 401 and 403) or bad JSON reads as `quota_unreachable`; a window sampled more than
   15 minutes ago reads as `quota_stale`; an executor with no series reads as
   `quota_missing`. Unknown is never scored as empty or full, and the route
   event lists each reason under `quota_unknown`. An executor with a
   live window at 95% or more drops out. The hook then ranks the eligible
   executors at call time: promotions by pace first, then, for the
   `bulk-complex`, `complex`, `plan` and `deep` classes, the remaining rows by
   pace with the harness rows last, and, for every other class and no class,
   the harness rows followed by the remaining rows by pace. Within one pace
   group, rows with a reading rank by distance (furthest under the line
   first, least over first); rows with no reading rank by price times peak
   multiplier, lowest first, then in table order.
   Executor rows live in `hooks/lib/policy.ts`, each with
   transport, trust and `private_ok`. `~/.config/ai-delegation/executors.json` (a JSON
   array of rows) overrides rows by `id` and adds new ones; invalid rows are
   logged and dropped, and only subscription-trusted rows may set
   `private_ok`; a sandbox row is always `sandbox-public` with `private_ok`
   false. A row with `kind: "promotion"` needs `expires` and, like every row,
   uses the `codex`, `sandbox` or `router-chat`
   transport. A `router-chat` row answers only what the local rung would
   take (`[class: text]`, never `[task: code]`) through the same
   `LITELLM_LOCAL_BASE_URL` chat call and the same size gate. An unpaid
   row must name an on-host alias (`small` or `local-only`) and be
   subscription-trusted with `private_ok` to see that work. A
   `billing: "paid"` row may name any router model; it carries
   `budget_daily_usd` (finite and positive; it documents the router key's
   own daily cap; the hook does not compare it) and `budget_key` (the router
   key alias), and is never `private_ok`. A paid row is eligible only for
   public work and only while `litellm_remaining_api_key_budget_metric` for
   that alias is fresh and above zero in the quota query result. No paid row
   can dispatch today: text work carries no public marker, and code work
   never reaches a router-chat row. `AGENT_ROUTE_ZCODE_TOOLS`, when set, limits which sandbox
   tools run; unset runs every table row's tool. Each `route` line lists
   `skipped` rows with a reason: `ineligible`, `exhausted`, `expired`,
   `not_installed`, `failed`, `recent_failures`, `budget_unknown` or
   `budget_spent`.
4. An executor failure, an empty answer or an unknown quota moves to the next
   executor; when no executor answers, the spawn is refused with `no non-Claude
   executor answered; nothing ran` and the route line records `stopped`. When
   an executor was cut off at its time limit, the refusal names it instead:
   `no non-Claude executor answered; <executor> timed out and may have left
   partial work` (one per timed-out executor, comma separated), together with
   the uncommitted paths `git status --porcelain` found in the directory the
   child worked in, so the lead checks partial work before re-sending the job.
   When an eligible executor was skipped for `recent_failures`, the refusal
   ends with `Retry after <time>.` (the earliest such executor's cooldown
   end, ISO 8601 UTC) and the route line carries `retry_after_ms`.
   Every routed result carries a `[fell through: <executor>: <reason>; ...]`
   line directly above its footer when earlier executors were tried, and the
   route line carries the same `reasons` map keyed by executor. Only
   forbidden models, retired agent types, prohibited payloads and a sandbox
   job that may still open a PR stop routing earlier.

For sandbox coding, put `[task: code] [repo: owner/repository]` in the
description. A public-repo tag alone does not establish that work is coding.
The sandbox takes public repositories only; a private repository stays with
Codex. The hook verifies the returned PR belongs to the requested
repository and is open and non-draft. When a job returns
no verified PR, the hook reads `zcode-job status <job>` and acts on its `end`
field. If the job ended without a PR, the task moves to the next eligible
executor; `fell_through_from` names the sandbox with its reason in `reasons`
and `skipped` gives `failed`.
A dispatcher that answers in full but names no job submitted nothing, so the
task moves on the same way. A truncated answer may hide a job, so it stops.
Every route line carries `hook_version`, the loaded plugin's version.
If the job ended `cancelled`, routing stops for that task: the hook writes its
outcome line and a route line with reason `sandbox job cancelled`. If the job is
still running, opened a PR, or has no readable `end`, the handoff fails; inspect
that job before retrying.

Every `route` line lists its sandbox jobs under `jobs` (`job`, `repo`,
`executor`, and `started_ms`, the hook's clock just before the start call).
When a later placement has a sandbox executor as a candidate, the hook reads the
last 128 KiB of the decision log; a truncated read counts as no history. It
reads `status` for up to five recent jobs that have no outcome yet, within 3
seconds in total, and writes one `outcome` line (`job`, `repo`, `executor`,
`end`, `ended_ms`, and a `reason` of `job <end state>` when the job ended
without its PR) for each job that has ended. `ended_ms` is the start plus the
job's `duration`, never later than the observation; without a duration it is
the observation time. The hook keeps no store of its own; it reads these lines
back from the decision log, counts one outcome per job, and ignores lines
stamped more than a minute in the future. An executor is skipped for a
repository with reason `recent_failures` when two or more of its last three
ended jobs there ended `no_commit`, `timeout`, `rate_limited` or `refused`. The
skip lasts 60 minutes after the newest failure's `ended_ms`, or until the end of
that UTC hour when it is `rate_limited`. Status reads on a failed start stop
after 15 seconds.
Routed child attempts also write one `outcome` line with `executor`, `end`
(`ok`, `failed`, `timeout` or `cancelled`) and `ended_ms`; prompt and answer text are never logged there.
A child an outside signal stopped, as when the session is restarted, ends `cancelled`; it is no executor fault and
never counts toward that cooldown.
Across repositories, three failures or timeouts in 60 minutes with no newer success skip an executor for 30 minutes after its newest failure.
The hook never merges. Leak-scan the exact PR head before any human merge.

The permission judge alone uses the GLM and OpenCode Go chat transports, through
`AGENT_ROUTE_GLM_MODEL` and `AGENT_ROUTE_OPENCODE_GO_MODEL` with `LLM_ROUTER_URL`
and `LLM_ROUTER_TOKEN_FILE`, or `LITELLM_LOCAL_BASE_URL`. Agent spawns marked
`[class: text]` go to the local rung instead. Supply all required text in the
prompt. Work requiring repository access, edits, tests or other tools continues
to a tool-capable executor. Coding tags, custom agents, `Explore`, `Plan` and
isolated tasks never take the local rung. An untagged spawn is classified by
the hook itself on the on-host `small` alias; every `route` line names the
outcome under `kind` (`value` `text`, `code` or `other` with `source` `tag`,
`classifier` or `none`).

Run `agent-route <code|private|other>` from the plugin root to inspect a
route. `code` means public coding; use `other` for read-only
work even in public repos. The helper reports a route; it does not dispatch or
verify the repository. `AGENT_ROUTE_CODEX_QUOTA=available|exhausted` and
`AGENT_ROUTE_ZCODE_AVAILABLE=yes|no` are test overrides.

## Second-opinion review (agy)

Antigravity (`agy`) gives an independent second opinion on a
high-risk diff. It is a reviewer, not an executor: it does not edit, merge, or
join the ladder. Use it on public repos and on trusted repos the operator names.

Non-interactive call, checked with `agy --help`:

```sh
agy -p="Read <brief-file> and review the diff it names. Reply with findings only, one per line: SEVERITY | file:line | issue." \
  --add-dir <dir-holding-brief-and-diff> --mode plan --output-format text
```

- `-p` takes its prompt as a value. It does not read stdin, so put the paths to
  the brief and diff inside the prompt, and pass their directory with `--add-dir`.
- The operator's configuration names the model; do not pin one in a brief or a
  command. `agy models` also lists Claude models, which this policy forbids here.
- `--mode plan` is the flag agy documents for plan mode. Its help does not say it
  blocks writes, so the brief must also say not to edit.
- Read stdout and the exit code. A non-zero exit or empty reply is a failed
  review. Never report it as a pass.

## Verification

Never ask an executor to merge, approve a gate, or use a credential. The trusted
lead verifies the exact PR, repository, base branch, diff, checks, and head SHA
before any merge. Classify the complete input before submission and leak-scan
the output before merge. Apply the prohibited-content rule to every executor
and second-opinion reviewer.

## Related skills

- **delegate-to-ai** (ai-delegation) — generic delegation guidance.
- **local-subagents** (ai-delegation) — local model menu and call contract.
- **multi-model-review** (ai-delegation) — independent review and synthesis.
- [Maintainer-specific routing and executor contract](references/estate-routing.md).
