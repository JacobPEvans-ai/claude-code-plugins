# Maintainer-specific delegation procedures

`jpe-ai-delegation` is enabled in the always-on `core` category. Its hooks
classify routable Agent calls, judge the bypass-immune shell-removal ask, and
put the session's `codex-quota` status in the system prompt.

The binding ladder order, sensitivity split, quota checks and eligibility
rules live in [the delegation-ladder skill](../SKILL.md); this page only adds
session mechanics.

## Session mechanics

The hook reads Codex quota from the metrics store at `AGENT_QUOTA_QUERY_URL`, not `codex-quota`.
The session status line says `available`, `exhausted` (a live window at 95% or
more) or `unavailable` (no usable quota row). None of these stops dispatch; a
failed Codex invocation moves to the next executor.

Mandatory topics override model selection and name `[class: bulk-complex]`;
explicit `plan` and `deep` tags retain their read-only sandbox. Codex routing
follows AGENTS.md, 'Delegation routing' in the shared instructions repository;
the command builder enforces its model and effort pair. `Explore` and `Plan`
spawns stay read-only. Sonnet, Opus and Fable choices are denied, including
custom-agent definitions. Worktree isolation creates a separate checkout for Codex rather
than selecting a later executor. Custom-agent instructions are loaded before
classification; unresolved definitions fail closed. An agent type the operator
retired in `~/.config/ai-delegation/retired.json` stops dispatch at once and
names the replacement command; the plugin ships no map, so a missing or
unreadable file retires nothing.

The permission judge answers the bypass-immune shell ask on the on-host
`medium` alias through `LITELLM_LOCAL_BASE_URL`, never spending the Codex
subscription. Any failure or unparsed verdict leaves the core dialog open for
the person; a failure never allows. Prohibited inline content is screened
locally before any classifier, judge or executor receives it; the lead
classifies all remaining context before dispatch.

## Executor contract

The main session is the trusted lead: it owns intent, scope, security decisions,
architecture, final verification, and user communication. Delegates execute
bounded work and return evidence; they do not change product intent or claim
completion on the lead's behalf. Keep private content and privileged actions on
approved local routes. Shared model-tier guidance is in
[model-tiers.md](../../../../ai-delegation/skills/premium-agent-orchestration/references/model-tiers.md).

## Repository and follow-up routing

Use one project thread per repository; see the
[claude-projects rule](https://github.com/dryvist/ai-llm-prompts/blob/main/auto-ai-agent/instructions/agentsmd/rules/on-demand/claude-projects.md).
File follow-up work as a Vikunja task, never a GitHub issue. Shared doctrine:
`prompt://dryvist/auto-ai-agent/model-delegation`.
