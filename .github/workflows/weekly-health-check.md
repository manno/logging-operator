---
description: |
  Weekly health check for the logging-operator SUSE rebuild pipeline.
  Monitors build status, auto-update bot liveness, open security/dependency PRs,
  and dependency drift. This is the meta-monitor for the CVE response pipeline —
  its job is to flag when the automation itself stalls, not to track feature
  work (we maintain frozen 4.10.0 application code).

on:
  schedule: weekly on monday
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: read
  actions: read

network: defaults

# Without this block, gh-aw v0.72.1 auto-injects a default create-issue
# handler. Declaring it explicitly keeps behavior stable across gh-aw upgrades.
safe-outputs:
  create-issue:
    max: 1
    title-prefix: "[weekly-health-check] "
    labels: [weekly-health-check, automated]

tools:
  bash: ["git:*", "gh:*", "sed", "grep", "cat", "echo", "date", "go:*", "curl", "jq", "docker:*"]
  github:
    toolsets: [actions, pull_requests]

timeout-minutes: 20
---

# Weekly Health Check — Logging Operator (SUSE Rebuild)

Generate the weekly health report for `${{ github.repository }}`.

This fork rebuilds upstream logging-operator with a fresh Go compiler, SUSE BCI
base image, and Go modules to address CVEs. Application code is **frozen at
4.10.0** — we do NOT cherry-pick. The release pipeline is fully automated:

- `auto-update-go.yaml` — daily; opens a PR when a new stable Go ships
- `auto-update-bci.yaml` — daily; opens a PR when the SUSE BCI digest changes
- `renovate.json5` — Go module updates (auto-merge on vuln + patch)
- `cve-response.md` — agentic CVE fix, triggered by image-scanning team

**This report's job is to catch when that automation stalls.** Skip anything
that doesn't speak to "is the rebuild pipeline producing fixed images?"

---

## Step 1 — Build status on rancher-main

Run:
```bash
gh run list --repo ${{ github.repository }} --branch rancher-main --limit 30 \
  --json conclusion,status,name,workflowName,createdAt,event,headSha,url
```

For each distinct `workflowName`, find the most recent run on `rancher-main`
and record: conclusion, age in hours, run URL. A failing run on `rancher-main`
blocks CVE-fix PRs from merging cleanly — these are top-priority signals.

Workflows to expect: `build`, `ci`, `e2e`, `codeql`, `release`, `artifacts`,
`auto-update-go`, `auto-update-bci`, `weekly-health-check`. If a workflow you
expect is missing from the list entirely, treat that as a finding (it has
never run on `rancher-main`, or has been disabled).

## Step 2 — Auto-update bot liveness

These two bots ARE the rebuild pipeline. If they stop running, CVE rebuilds
stop happening — this is the most important section.

For each of `auto-update-go.yaml` and `auto-update-bci.yaml`:
```bash
gh run list --repo ${{ github.repository }} --workflow <file> --limit 5 \
  --json conclusion,createdAt,event,url
```

Record per bot:
- Age of the most recent successful run (expected: < 36 h, since they run daily)
- Conclusion of the last 5 runs (success rate)
- Whether there's an open PR from that bot. Detect by branch prefix:
  ```bash
  # auto-update-go: branches like auto-update-go-1.26.4
  gh pr list --repo ${{ github.repository }} --state open --search "head:auto-update-go-" \
    --json number,title,createdAt,url
  # auto-update-bci: single branch
  gh pr list --repo ${{ github.repository }} --state open --head "auto-update-suse-bci" \
    --json number,title,createdAt,url
  ```

**Escalation rules** (must appear in High Priority action items):
- Last successful run > 36 h ago → bot stalled
- Most recent run failed → investigate before next scheduled run
- Open PR from bot is older than 7 days with green checks → why hasn't it merged?

## Step 3 — Open PR analysis

```bash
gh pr list --repo ${{ github.repository }} --state open --limit 50 \
  --json number,title,labels,createdAt,updatedAt,author,isDraft,url,headRefName,statusCheckRollup
```

Group by the labels the bots emit. Each PR is counted in **at most one**
group; precedence top-to-bottom:

| Group | Label(s) | Source | Why we care |
|---|---|---|---|
| CVE fixes | `cve-fix` | `cve-response.md` | Active CVE remediation |
| Security | `security`, `vulnerability` | Renovate vuln alerts | Should auto-merge |
| Go compiler | `go-update` | `auto-update-go.yaml` | Stdlib CVE rebuild |
| SUSE BCI | `suse-bci-update` | `auto-update-bci.yaml` | OS-level CVE rebuild |
| Other deps | `dependencies` | Renovate | Module updates |
| Untagged | (none of above) | Manual | Probably needs triage |

For each group: count, oldest PR age in days, count with failing checks.

**Escalation rules:**
- Any `cve-fix` PR open > 3 days → review escalation
- Any `security`/`vulnerability` PR present (Renovate is configured to
  auto-merge these) → auto-merge failed; investigate why
- Any group with failing checks → list the PRs

## Step 4 — Dependency drift (cross-check against bots)

The point of this section is not just "is X out of date" — the auto-update
bots already check that daily. The point is: **if drift exists AND no open
auto-update PR exists, the bot failed silently.**

**Go compiler:**
```bash
CURRENT_GO=$(cat .go-version)
LATEST_GO=$(curl -fsSL 'https://go.dev/dl/?mode=json' \
  | jq -r '[.[] | select(.stable == true)] | .[0].version' | sed 's/go//')
echo "go current=$CURRENT_GO latest=$LATEST_GO"
```
If `CURRENT_GO != LATEST_GO` and Step 2 found no open `auto-update-go` PR,
flag as **High Priority** (bot is silently broken — drift it should have
caught is sitting open).

**SUSE BCI base image:**
```bash
CURRENT_BCI=$(grep -E '^FROM .*bci-micro' Dockerfile.suse | sed -n 's/.*@\(sha256:[a-f0-9]*\).*/\1/p')
LATEST_BCI=$(docker buildx imagetools inspect registry.suse.com/bci/bci-micro:latest \
  --format '{{json .}}' 2>/dev/null | jq -r '.manifest.digest' || echo unknown)
BCI_AGE=$(git log -1 --format=%cr -- Dockerfile.suse)
echo "bci current=$CURRENT_BCI latest=$LATEST_BCI last_bumped=$BCI_AGE"
```
Same logic: drift + no open `auto-update-suse-bci` PR → bot stalled. Also
report the last-bumped relative time so reviewers can sanity-check.

**Go module vulnerabilities:**
```bash
go install golang.org/x/vuln/cmd/govulncheck@latest
"$(go env GOPATH)/bin/govulncheck" -mode=source -show=verbose ./... 2>&1 | tail -200 || true
```
Report the count of vulnerabilities affecting our build (govulncheck filters
to actually-called code paths). For each: ID, affected module, fixed version
if any. **If any vulnerability has a fixed version available, that is High
Priority** — Renovate's vuln auto-merge should have caught it.

## Step 5 — Emit the report

**Emit the full markdown report as your final response.** The `safe-outputs`
handler declared in the frontmatter will turn it into a GitHub issue
(prefix `[weekly-health-check]`, labels `weekly-health-check, automated`).
The first `# heading` line becomes the issue title; everything after becomes
the issue body. The report is ALSO rendered to the workflow run's step
summary automatically.

Use exactly this structure (substitute the bracketed placeholders with real
data from steps 1–4):

```markdown
# Health Report — Week of <YYYY-MM-DD>

## Weekly Health Report — Logging Operator (SUSE Rebuild)

**Repository**: `${{ github.repository }}`
**Report date**: <YYYY-MM-DD>
**Branch**: `rancher-main`
**Pipeline status**: <one-line: 🟢 healthy / 🟡 drift / 🔴 broken>

---

### Build health (most recent run per workflow on `rancher-main`)

| Workflow | Conclusion | Age | Run |
|---|---|---|---|
| build | ✅/❌ | Xh | <url> |
| ci | ✅/❌ | Xh | <url> |
| e2e | ✅/❌ | Xh | <url> |
| codeql | ✅/❌ | Xh | <url> |
| release | ✅/❌ | Xh | <url> |
| artifacts | ✅/❌ | Xh | <url> |

<If any failed, list one bullet per failure with run URL.>

---

### Auto-update bot liveness

| Bot | Last success | Last 5 runs | Open PR |
|---|---|---|---|
| auto-update-go | Xh ago | ✅✅✅✅✅ | #N or none |
| auto-update-bci | Xh ago | ✅✅✅✅✅ | #N or none |

<If a bot stalled (no success in >36h, OR last run failed):>
> 🚨 **<bot> stalled** — last successful run Xh ago. The rebuild pipeline
> is not running. See <run-url>.

---

### Open PRs

| Group | Count | Oldest | Failing checks |
|---|---|---|---|
| cve-fix | X | Nd | Y |
| security / vulnerability | X | Nd | Y |
| go-update | X | Nd | Y |
| suse-bci-update | X | Nd | Y |
| dependencies (other) | X | Nd | Y |
| untagged | X | Nd | Y |

<List any escalations: stale cve-fix PRs, security PRs that didn't auto-merge,
auto-update PRs with failing checks. Skip the section if there are none.>

---

### Dependency drift

| Component | Current | Latest | Status |
|---|---|---|---|
| Go compiler | <ver> | <ver> | ✅ in sync / ⚠️ drift / 🚨 drift + bot silent |
| SUSE BCI digest | `<short>` | `<short>` | ✅ / ⚠️ / 🚨 (last bumped <relative-time>) |
| Go module vulns | N found | — | ✅ clean / ⚠️ N with no fix / 🚨 N with fix available |

<If govulncheck found any vulns, list them: ID, module, current vs fixed.>

---

### 🎯 Action items

Generate strictly from the data above. If a section has nothing, write
"None." rather than padding.

**High priority** (rebuild pipeline broken or unfixed CVE with known fix):
- ...

**Medium priority** (drift accumulating but not actively breaking):
- ...

**Low priority** (nuisance / housekeeping):
- ...

---

📅 **Next report**: <next Monday date>
🤖 Generated by [Weekly Health Check](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})

<!-- gh-aw-workflow-id: weekly-health-check -->
```

That markdown block IS your final response — emit it verbatim with placeholders
filled in. Do not run any further tool calls after emitting it; the safe-output
handler takes it from there.
