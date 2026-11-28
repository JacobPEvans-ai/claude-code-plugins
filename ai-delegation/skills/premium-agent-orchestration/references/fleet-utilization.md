# Fleet utilization

An orchestrator keeps every worker and its subagents busy so no session's
cached context is wasted. This file is the procedure behind the skill's
"Keep the fleet working" section. Read that section for the rule; read this
file to run it.

## 1. States

A session is in exactly one of three states:

- **Working**: it holds an in-flight item.
- **Waiting**: it waits on a named event with a background wake condition
  while its next item runs. The wait is a monitor, not a block.
- **Closed**: it has written its resume state and holds nothing.

Idle is not a state. An idle session wastes its warm prompt cache and then
costs a full re-read when it wakes cold.

## 2. Queue

Each worker keeps a ranked queue of at least three independent items in its
report file, and each item carries a named yes/no check. While a review, a
CI run, or a deploy runs, the worker starts the next item instead of
watching the running one.
Every wait is a background monitor with a wake condition; a worker never
sits blocked. The monitor wakes the session when the job ends; a wake
whose only content is "still waiting" is a keep-warm ping (§6).

## 3. Session monitors

The lead holds one background monitor on each worker's state, and one worker
holds a monitor on the lead. No model runs a timed sweep. A session idle or
blocked for 15 minutes gets one nudge. With no reply in 5 minutes it is
restarted from its brief and report file. A worker whose queue is empty or
fully blocked tells the lead, which assigns work or closes the session.

## 4. Milestone reports

A worker reports at each milestone, in one line: what finished, with its
proof, and its next item.

## 5. Fan-out

A worker with independent items runs them concurrently; the delegation hook
places each spawn. Size the fan-out to the work and to measured machine
load, never to a fixed cap. The skill's "Substrate resilience" section
governs live availability and limits; this rule adds utilization, not new
caps.

## 6. No keep-warm pings

A message carries real work or a real check. Never send a message whose
only purpose is to keep a prompt cache warm. A session with nothing
assignable writes its resume state and is closed. An empty queue is a
signal to the lead, never a reason to invent work.

## 7. Resume state

Before a wait that nothing can fill, the worker writes its resume state:
what is in flight, its timers, and its next step. A closed session resumes
from this state alone.

## 8. Measure

The lead's periodic report carries two fleet numbers: busy sessions out of
total sessions, and idle minutes per period.

## 9. Exceptions

The lead reads exceptions only: empty queue, blocked, missed checkpoint,
failed proof. Everything else stays in each worker's report file until a
check or a review calls for it.
