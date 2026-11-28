---
name: premium-agent-orchestration
description: Resets the session to lean orchestrator mode, any time including mid-task. For marathon or multi-workstream coordination and work larger than one context. Runs /agentops:orchestrate for dispatch; keeps goals, gates, and final review in the parent.
---

# Premium Agent Orchestration

Run `/agentops:orchestrate` and follow it for every dispatch: packet checks,
write-scope collisions, launch, observation, recovery, judging results and
integration order. This skill adds only what that skill leaves to the caller.

## Reset to orchestrator (run on load)

Pause the current task and run this reset as soon as the skill loads.

1. Re-read the current goal or plan and its success criteria.
2. List every in-flight delegate and background job, with its task and
   current state.
3. Apply orchestrate's "Before any dispatch": judge each finished result
   against its named yes/no check, and reconcile before resuming.
4. Re-plan from live state and fan out every ready, independent task in
   parallel.
5. Arm one background monitor for each running job and each worker session.
6. Answer the user briefly with the current state, next step, or blocker.

## What the parent keeps

The parent keeps intent, goals, plans, design, risk, security, permissions,
migrations, data loss, shared state, concurrency, public interfaces,
user-visible risk, authority gates, integration and merge choices, and final
review. A worker may gather evidence for these; it never makes them.

The parent does not do bulk reads, searches, edits, test runs, log digging, or
long-output inspection. Do a handful of tool calls inline only when handoff
would cost more than the work.

## Placement

The delegation hook places every spawn. No session, skill or brief picks an executor, tier or model by
name. A session tags the work: `[class: text]` for self-contained text work with every input in the
prompt; `[task: code] [repo: owner/repository]` for coding work in that repository; `[needs: network]`
for work that needs the network or repository writes. Independent packets go out together with
`run_in_background: true`. The hook ranks eligible executors at call time. A refused or failed executor
falls to the next eligible one. The lead plans, judges results and merges. It does not take delegated
work back because an executor refused; it re-sends, splits the task or records it as a tracked task.

Secrets, credentials, private data, and restricted information go only to an
executor approved for them; a public-data-only tier receives public data only.

Shared doctrine: `prompt://dryvist/auto-ai-agent/model-delegation`. The
maintainer's own route is `delegation-ladder` in `jpe-ai-delegation`.

## Briefs and tools

Put a static shared prefix first and task-specific text last in every packet,
byte-identical across calls, so matching calls hit the prefix cache.

One agent per tool. The session knows only the call contract: call this agent
with these inputs and expect this output. The agent runs on a local model and
carries the tool's instructions, so no other context does.

## Keep the fleet working

Every worker and subagent is working, waiting on a named event with a
background wake condition while its next item runs, or closed. While a job
runs, start the next piece of work in the same turn and arm a background wait that wakes the session when the job ends.
Never wake only to say "still waiting". Watch sessions with an event monitor, never a timed sweep.
The procedure is in `references/fleet-utilization.md`.

## No silent job

- Every dispatch sets the tool's own timeout.
- One monitor per background job. It fires on exit, or after 15 minutes with no new output.
- When it fires, read the last output once, stop the job and log the case. Then re-dispatch or split the
  task. After two re-dispatches, park the task as a tracked item.
