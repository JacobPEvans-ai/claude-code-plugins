---
name: promote-release
description: >-
  Drives the automatic promote/<version> promotion PR into main on git-flow
  repos: confirm the release-please PR merged on develop, merge the promotion
  with a merge commit, and verify the release-please tag. Refuses on trunk
  repos — use /merge-pr.
---

# Promote Release

On git-flow repos (default `develop`, production `main`), the shared
`JacobPEvans/.github/.github/workflows/_promotion-pr.yml` workflow owns
promotion. It runs when a release commit (`chore(develop): release
<version>`) lands on `develop`, on any push to `main`, and on a weekly cron.
It creates `promote/<version>` at the newest release commit on `develop` that
`main` lacks, opens a PR from `promote/<version>` to `main` titled
`chore(release): promote <version> to main`, and arms auto-merge with a merge
commit. At most one promotion is open at a time: merging it pushes `main`,
which opens the next promotion if one is waiting, and the branch is deleted
on merge.

While a promotion is open, `develop` is never frozen and carries no
promotion-state labels; work keeps landing on `develop` normally. The
promotion PR runs the full CI tier and the Main Source Gate, which accepts
`develop`, `hotfix/<name>`, and `promote/<version>` heads. Release-please
tags the release commit on `main` as before; if a newer release is still
waiting when the merge lands, its tag waits for the promotion that carries
it.

This skill confirms the release-please PR merged on `develop`, then drives
the open promotion PR to merged with a merge commit.

> **State warning**: PR status, CI, and branch state change between
> invocations. Re-run every git/gh command from Step 0.

## Critical Rules

- **Merge commit only** for promotions into `main`. Never squash or rebase —
  `main`'s ruleset bans both. See /gh-cli-patterns Canonical
  Default-Branch Detection.
- This skill does **not** run on trunk repos. Step 0 refuses immediately if
  the repo's default branch is `main`.
- Never hand-create the promotion PR: no PR with a `develop` head into
  `main`, no `gh pr update-branch` on it, no pushing to
  `promote/<version>`. The shared workflow owns promotion branches, and the
  release-please commit is never edited.
- Never invent a version, write CHANGELOG entries, create release PRs, or tag
  by hand. Release-please prepares the release on `develop` and tags the
  promoted commit on `main`.
- `release/*` stabilization branches are out of scope for this workflow.

## Step 0: Confirm Git-Flow Repo

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
```

If `DEFAULT_BRANCH != develop`, **abort**:

> "This repo's default branch is `{DEFAULT_BRANCH}`, not `develop` — it is not
> on the git-flow model. There is no promotion to `main` here; use
> `/merge-pr` for ordinary PRs into `{DEFAULT_BRANCH}`."

## Step 1: Confirm the Release-Please PR Merged on Develop

```bash
git fetch origin --force develop main
gh pr list --base develop --state merged --limit 20 \
  --json number,headRefName,mergedAt \
  --jq '.[] | select(.headRefName | startswith("release-please--"))'
```

The newest merged release-please PR's release commit
(`chore(develop): release <version>`) must be on `origin/develop` and ahead
of `origin/main`. Inspect what the promotion will carry:

```bash
git log --oneline origin/main..origin/develop   # newest entry is the release commit
```

If `develop` has no commits ahead of `main`, **stop** and report: "`develop`
has no commits ahead of `main` — nothing to promote." If the newest
release-please PR is still open on `develop`, wait for its auto-merge or
merge it first with `/merge-pr <RELEASE_PR_NUMBER> --squash`.

## Step 2: Find the Open Promotion PR

The shared promotion workflow creates the promotion PR automatically. Find
it:

```bash
gh pr list --base main --state open --json number,headRefName,url \
  --jq '.[] | select(.headRefName | startswith("promote/"))'
```

Use the PR it returns — it is titled `chore(release): promote <version> to
main` and has auto-merge armed with a merge commit.

If none is open, **stop** and report: "No promotion PR is open. The promotion
workflow opens one automatically on the next release commit pushed to
`develop` or the next push to `main`." Never create a `develop`-headed PR
into `main` by hand.

## Step 3: Validate the Promotion

Check that `develop` itself is green — `gh run list --branch develop --limit
3` and the newest run must be complete/success — then check every check run
and commit status on the promotion PR's head, which includes the full CI
tier and the Main Source Gate (the gate accepts `develop`, `hotfix/<name>`,
and `promote/<version>` heads):

```bash
gh pr checks <PR_NUMBER>
gh api repos/<OWNER>/<REPO>/commits/<SHA>/check-runs
gh api repos/<OWNER>/<REPO>/commits/<SHA>/status
```

All must be green. If any check or status fails, **stop** and report the
failing checks: do not merge the promotion. Fix the failure through a PR on
`develop`; the next promotion carries the fix.

## Step 4: Check Promotion Readiness

Run the **canonical PR-readiness gate** from /gh-cli-patterns against the
promotion PR:

1. Fetch and verify HEAD is not behind.
2. Re-mergeable (`canMerge: true`) with all mergeability flags clean.
3. All checks green, including the Main Source Gate.
4. Labels are exactly the repo standard set.

If any **soft block** remains, run `/finalize-pr <PR_NUMBER>` and re-run the
gate. If any **hard block** remains, stop and report — do not merge.

## Step 5: Merge Commit Into Main

Invoke `/merge-pr <PR_NUMBER>`, which validates the promotion PR and merges
it into `main` with a merge commit — never squash, never rebase. The
`promote/<version>` branch is deleted on merge, and the push to `main`
triggers the shared workflow to open the next promotion if one is waiting.

## Step 6: Report and Verify the Tag

Release-please tags the release commit on `main` as before. Verify the tag
and its content:

```bash
git fetch origin --tags
git ls-remote --tags origin
gh release view <VERSION>
git show <VERSION>:CHANGELOG.md
```

Report the promotion PR number and URL, the merged commit, and the verified
tag. If a newer release was still waiting when this merge landed, its tag
waits for the promotion that carries it — report that the next promotion is
pending rather than inventing the tag.

## Related Skills

- merge-pr (github-workflows) — invoked to merge the release-please PR (squash)
  and the promotion PR (merge commit)
- gh-cli-patterns (github-workflows) — canonical PR-readiness gate and
  merge-method enforcement table
- pr-standards (github-workflows) — merge-commit-only rule for production
  branches
