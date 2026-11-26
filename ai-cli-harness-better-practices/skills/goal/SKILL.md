---
name: goal
description: "Emit a /goal line for the work in flight, under 4000 chars. Derives focus from the session, then runs goal-prompt, or /agentops:craft-goal for multi-experiment campaigns."
---

# Goal

A wrapper. It gathers inputs from this session, passes the drafting to a pre-built skill, and adds only this
workspace's rules and the measured count. It writes no files and makes no git, `gh` or network calls.

## 1. Focus

An argument **is** the focus, like a `/compact` hint. Honor its exclusions literally. With no argument, derive the
focus from these sources, highest weight first, and skip any that are absent:

1. The most recent pivot in the conversation.
2. Unchecked `- [ ]` items in the plan file named by the latest `## Plan File Info:` system reminder.
3. `TaskList` entries whose status is not `completed`.

When sources disagree, the conversation wins.

## 2. Route

- **Default: `goal-prompt`** (trailofbits). Pass it the focus and the facts that ground it: absolute paths, the
  check command, invariants and a stop bound.
- **`/agentops:craft-goal`** only when the focus needs several related experiments with numeric budgets. Relay its
  decision line unchanged. On `USE_PLAN`, use `goal-prompt` instead. On `UNSAFE_GOAL`, relay the missing decisions.
- If the skill you need is not installed, name it and stop. Never draft the goal yourself.

Give the chosen skill these rules as constraints. If its output breaks one, run it again with the fix.

| Rule | Why |
| --- | --- |
| Absolute paths; full URLs for any PR, issue or ticket | A bare `#123` cannot be resolved cold |
| No secret values, hostnames, IPs or internal topology; name where a value lives | The line gets pasted into other tools and logs |
| Self-contained: no "continue where you left off" | The reader has no memory of this session |

## 3. Measure and print

Measure exactly what will be pasted. A UTF-8 locale is required, because `wc -m` counts bytes under `C`:

```bash
LC_ALL=en_US.UTF-8 wc -m <<'GOAL_EOF'
<the goal text, verbatim>
GOAL_EOF
```

When invoked directly, print the skill's output unchanged, followed by `chars: <N>`. When invoked by another skill,
return `chars: <N>` on the first line and the goal text after it. A craft-goal prompt over 4,000 characters is too
long for `/goal`: say so in one line and offer it as a session prompt instead.
