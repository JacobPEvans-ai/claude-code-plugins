---
name: local-subagents
description: Use for bulk reading, summarizing, classifying, extracting, drafting boilerplate, or a first pass over code — self-contained text work tagged and sent out. Covers delegation timing, the live model menu, bounding calls, refusals.
license: MIT
metadata:
  version: 1.0.0
  author: ai-delegation maintainers
  hermes:
    category: research
    tags:
      - delegation
      - routing
      - models
      - cost
      - local
    related_skills:
      - openrouter-models
      - premium-agent-orchestration
---

# local-subagents

Shared doctrine: `prompt://dryvist/auto-ai-agent/model-delegation`. The
delegation hook places every spawn; a session tags the work and never picks
an executor, tier or model by name. This skill covers the mechanics around
that rule: when work qualifies for delegation, how to bound a call, and how
to read a refusal.

## 1. When to delegate — the default is yes

Delegate a step when its result can be **checked from concrete evidence**:

| Delegate | Keep |
| --- | --- |
| Summarizing a file, log, or diff | What the user actually wants |
| Classifying or triaging a batch | Architecture and design choices |
| Extracting structured fields into a schema | Tradeoffs, risk, security judgment |
| A first pass over unfamiliar code ("where is X handled") | Resolving contradictory evidence |
| Drafting boilerplate text from a stated pattern | Reviewing anything risky |
| Reading and reducing command or test output | The final answer to the user |
| | Code edits — the router never writes code; tag them `[task: code] [repo: owner/repository]` |

Two rules that keep this honest:

- **Split the job; never escalate the whole job.** One hard step inside a task
  does not make the task premium work. Delegate the other eight steps.
- **Capable judges the subtask, not the parent task.** A minimal model summarizing
  a log is the right tool even inside a hard architectural task.
- **Router entries earn re-checkable lookups and bulk reads, not code edits.**
  Delegate to a router entry only when the result can be verified against
  concrete evidence (a grep hit, a test pass, a schema match). Code edits are
  `[task: code] [repo: owner/repository]` work. A misread search or a
  silently wrong edit costs more than it saves.

## 1b. Verify, then re-send only the failures

When a delegated batch has a verification command (a test, a lint, a diff
against expected output), run the verification per item and re-send only
what failed:

1. Send the whole batch as one tagged packet.
2. Run the verification command per item.
3. Re-send only the failing items. Never re-send items that
   already passed.
4. A refused or failed executor falls to the next eligible one. An item
   still failing is split or recorded as a tracked task, not absorbed
   silently.

It only works with a verification command; without one, say the result is
unverified.

**Never delegated, at any tier:** secrets and credentials, secret-store
context, private infrastructure topology (hosts, addresses, what depends on
what), personal data, and anything a free-tier entry's caveat forbids. Those
stay with you or go to a local entry only.

## 2. Read your endpoint from the environment

The router is an OpenAI-compatible endpoint. Its base URL and credential
arrive as environment variables whose names are set by whatever provisioned
the session — read them, never assume:

```sh
env | grep -iE 'router|litellm|openai_(base|api)' | sed 's/=.*/=<set>/'
```

A credential may arrive as a **file path** rather than a value; read the file
at the moment of the call and keep it in a variable, never export it.

No endpoint variable means the router is not wired into this session. Say so;
the hook's fall-through places the work with the next eligible executor. Do
not go looking for a provider key — you hold none, and acquiring one
replaces a central budget with an unmetered one.

## 3. Fetch the live menu — never hardcode a model name

Inventories change far faster than this skill. Fetch:

```sh
curl -fsS --max-time 10 -H "Authorization: Bearer $ROUTER_KEY" \
  "$ROUTER_BASE/model/info" > menu.json
```

Render the menu before a call. Entries may publish a `hints` map
(`speed`, `quality`, `best_for`, `caveats`, `measured`) — the registry's own
description of each model, which is why this skill needs no model names:

```sh
jq -r '.data[] | [ .model_name,
    (.model_info.hints.speed // "?"), (.model_info.hints.quality // "?"),
    ((.model_info.hints.best_for // []) | join("/")),
    (.model_info.max_input_tokens // 0 | tostring),
    (if (.model_info.input_cost_per_token // 0) == 0 then "free" else "paid" end),
    ((.model_info.hints.caveats // []) | join(","))
  ] | @tsv' menu.json | sort -k6,6 -k2,2
```

`$ROUTER_BASE` is expected to already include the API version. If the variable
you found does not, add the version segment before appending these paths.
Fallback listing when `/model/info` is unavailable: `GET /models` gives ids
only, no hints — say so if you choose from it. More recipes:
[references/menu.md](references/menu.md).

## 4. Read the menu, size the call

The hook ranks the eligible executors at call time; this session never picks
one by name. The menu still bounds the call:

1. **Check the context window against your input** before sending. A router
   with pre-call checks refuses an oversized prompt outright rather than
   truncating it — that refusal is correct, and the fix is a smaller slice or
   an entry with a larger window, never a retry.
2. **Read the caveats.** They are measured failure modes: a model that only
   tool-calls reliably in one stream, one that needs specific sampling, one
   whose free tier retains prompts.

When no hints are published, say the call was sized without them.

## 5. Call, bounded

```sh
curl -fsS --max-time 120 -H "Authorization: Bearer $ROUTER_KEY" \
  -H 'content-type: application/json' \
  -d @request.json "$ROUTER_BASE/chat/completions"
```

- **Every call gets a timeout.** A local model is slower than a hosted one;
  size the timeout from the entry's `speed` class, and treat a slow entry as
  slow, not hung.
- **Send only what the subtask needs.** A delegated call carrying your whole
  conversation costs more than doing the work yourself and widens what leaves
  your environment.
- **Write the prompt for a small model**: short imperatives, an explicit
  output schema, a row cap, and a hard STOP. Ask for extraction, never advice.

```text
Extract items from the input. Do not explain. Do not advise. Do not fix.
Output ONLY this table, one row per item:
  item | kind | state | evidence (line no, URL, or quote)
Rules:
1. Copy text verbatim. Never paraphrase an item.
2. Unknown field -> write UNKNOWN. Never guess.
3. At most 60 rows. STOP after the table.
```

- **Bound fan-out.** Many local backends serve one request at a time and
  refuse rather than queue. Two or three in flight, never an unbounded batch.

## 6. When the router says no

| What you see | What it means | What to do |
| --- | --- | --- |
| DNS failure, refused connection, timeout | Router unreachable | Report it; defer the subtask, split it, or record it as a tracked task |
| `401` / `403` | Credential invalid or not scoped to that model | Report it; do not retry with a different credential |
| `429` | Backend busy — often a single-slot local model, or `fast-gpu`'s contention lock (§8 — `fast`/`subagent` redirect instead of returning this) | Wait once and retry, or let placement fall to the next eligible executor; see `openrouter-models` for budget refusals |
| `400` naming an unknown model | Your id is not served | Re-fetch the menu; do not retry the same id |
| A context-length refusal | Pre-call check working | Send a smaller slice or pick a larger-window entry |

None of these authorize a silent fallback. Absorbing the work back into your
own context without saying so is the exact cost the delegation was meant to
avoid, and it hides the failure from whoever pays for it. Never respond to any
of them by reaching for a provider credential.

## 7. Report what you used

Name the alias that produced each delegated result, and say when you chose
without hints, used the id-only listing, or did the work yourself because the
router was unreachable. A reader weighing your output needs to know which
parts came from a cheap tier. For a role that redirects instead of failing
(§8), name what the response says actually answered — not just the role you
called; the two can differ.

## 8. Fast local roles — `fast-gpu` visible, `fast`/`subagent` silent

The router publishes more than one role for local-first work, and they do
not behave the same way under contention. Ask the menu (§3) for what is
current — this is a behavioral split, not just a name, so verify before
relying on it.

- **`fast-gpu` surfaces contention as a `429`.** Its body names the current
  holder and a retry hint — respect it. Wait once for the hinted interval,
  or let placement fall to the next eligible executor as a stated
  choice per §6. Do not loop-poll or hammer it; that only extends the wait
  for whoever is already holding it.
- **`fast` and `subagent` never surface contention.** Rather than failing,
  they redirect through their own fallback ladder and answer from whichever
  rung was free — silently. Do not expect a `429` as a busy signal from
  either of these, and do not assume the reply came from the fastest rung:
  check whatever field the router's response publishes for what actually
  answered (§7) before reporting it as this tier.
- **None of these are more capable than you.** Route only Delegate-column
  work here (§1) — menial, routine, checkable — no matter which of these
  roles answers.
- **Never a silent default.** A delegated call reaches one of these roles
  only when the hook's placement names it. A caller
  may configure one as an automatic fallback on its own side — that does not
  extend to this skill's callers.

## Related skills

- **openrouter-models** (ai-delegation) — the self-enforced spend budget for
  paid entries, the free-tier prompt-logging rule, and how to ask for a model
  the router does not serve.
- **premium-agent-orchestration** (ai-delegation) — which decisions a premium
  session keeps; the delegation hook places its spawns.
- **`/agentops:orchestrate`** — dispatch and result checks for work sent to
  another harness or CLI rather than to a model behind the router; the
  maintainer-specific executor ladder is in `jpe-ai-delegation`.
