---
name: semaphore-converge
description: Use whenever a task needs a Semaphore converge (an Ansible template run) in the maintainer's estate. Never touch Semaphore directly; ask the router's converge agent for a preview, then run one confirmed template by id.
---

# Semaphore converge

Every converge in the maintainer's estate goes through one agent: the router
model `agent-semaphore-converge`. It is the only caller that holds a Semaphore
write token. Claude Code, Codex, Antigravity, Hermes and a person in the
router's chat UI all ask it the same way. This skill is the whole caller
contract and must work loaded alone.

## Never

- Never call the Semaphore API, its MCP server or its web UI yourself, and
  never read or ask for a Semaphore token. The agent holds the only one.
- Never start a run from a description. A run needs a preview first and then
  the exact template id.
- Never ask for check mode or dry-run. These playbooks are not check-mode safe.
- Never retry, rerun or "fix forward" a failed run on your own. Report it.
- Never run a converge that the operator did not ask for in their own words,
  and never as a test.

## How to call it

One request per call, through the shared router, with the
`fast-subagent.sh` script in the `fast-subagent` skill's `scripts/` directory
(ai-delegation; deployed under `~/.agents/skills/fast-subagent/`). It finds the
router from `LLM_ROUTER_URL` and `LLM_ROUTER_TOKEN_FILE`; exit 2
means this session cannot reach the router, so say so and stop.

```sh
printf '%s\n' "[caller=<harness> request=<id>]" "<request>" \
  | fast-subagent.sh --model agent-semaphore-converge --max-tokens 4096 --timeout 900 \
      --system 'Follow your own rules.'
```

The first line is a label for the run's message, so the operator can trace it.
The agent answers with one JSON object:
`{"status":"ok"|"refused"|"stop","reason":...,"result":...}`.

## The three requests

1. **Preview.** Name what should converge in plain words, for example
   `preview the template that converges the LLM router`. The agent reads the
   template, its playbook and arguments, the last successful run and anything
   running or queued in the project, and answers `"stop"` with that preview
   and the exact confirm line. Show the preview to the operator.
2. **Run.** Only after the operator says yes to that preview, send its confirm
   line: `run template <id>`, plus a limit or arguments only if the operator
   gave them word for word. A limit must include `localhost`. One template per
   request.
3. **Status.** A long run comes back `"ok"` with `"outcome":"running"` and a
   task id. Ask `status of task <id>` later; do not start another run.

To stop a run, send `stop task <id>` with the exact task id, and only on the
operator's word.

## Reading the answer

- `"outcome":"verified"` means the task succeeded and every host in its PLAY
  RECAP shows `failed=0` and `unreachable=0`. Nothing less is a success.
- `"refused"` is final for that request. Common causes: another task is
  running or queued in the project (the agent never queues behind it), a
  missing or unknown id, a limit without `localhost`. Report the reason.
- A failure carries the agent's failure analysis. Pass it on; do not act on it
  without the operator.
- Exit 3 from the script is an auth refusal: this harness's router key does not
  hold the agent. Report it; never borrow another key.
- A `400` naming an unknown model means the agent is switched off on this
  router. Report it; there is no fallback path to Semaphore.

## From the router's chat UI

A person can pick `agent-semaphore-converge` as the model in the router's chat
UI and send the same three requests, one per message.
