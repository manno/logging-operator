# GitHub Workflows for Logging Operator

This directory contains both traditional YAML workflows and GitHub Agentic Workflows (AI-powered) for automating builds, security, and maintenance tasks.

## Agentic Workflows (AI-Powered)

These are written in Markdown with natural language instructions, executed by AI agents.

### 1. CVE Response (`cve-response.md`)

**Triggers**:
- `workflow_dispatch` with `issue_url` input - called by the security team's image-scanning repo
- Slash command `/fix-cve` on local issues (manual/testing)

**Purpose**: Automatically analyze CVEs and create PRs with build environment updates

**Image-scanning integration:**

The security team's image-scanning repository triggers this workflow:
```bash
gh workflow run cve-response \
  --repo manno/logging-operator \
  -f issue_url=https://github.com/<scanning-org>/<scanning-repo>/issues/<number>
```

The CVE issue stays in the image-scanning repo - we don't mirror it locally.

**Manual usage:**
```
/fix-cve
```

Comment on a local CVE issue to trigger.

**What it does:**
1. Fetches CVE issue (from external image-scanning repo or local issue)
2. Determines fix strategy (Go compiler update, SUSE BCI update, or Go module update)
3. Verifies fix is available (new Go version, BCI digest, or module version)
4. Creates a branch with the updated build environment
5. Opens a PR for review
6. Comments back on the source issue with the PR link

**Important:** We maintain frozen application code (4.10.0). Fixes come from rebuilding with updated dependencies, not code changes.

### 2. Weekly Health Check (`weekly-health-check.md`)

**Trigger**: Scheduled (Mondays at 6:57 AM UTC)  
**Purpose**: Weekly repository health monitoring

**Manual trigger:**
```bash
gh workflow run weekly-health-check.md
```

**What it does:**
1. Checks build status
2. Analyzes open issues and PRs
3. Checks dependency freshness (Go compiler, SUSE BCI, Go modules)
4. Checks for security vulnerabilities in dependencies
5. Creates a health report issue with action items

---

## Traditional YAML Workflows

These are standard GitHub Actions workflows for building and updating images.

### 1. Build (`build.yaml`)

**Trigger**: Push to rancher-main, tags, PRs  
**Purpose**: Build and push multi-arch SUSE images

**Manual trigger:**
```bash
gh workflow run build.yaml
```

**What it does:**
1. Sets up multi-arch build environment
2. Builds logging-operator using Dockerfile.suse
3. Creates linux/amd64 and linux/arm64 images
4. Pushes to GHCR (ghcr.io/manno/logging-operator)
5. Tags with version or dev-commit

### 2. Auto-Update Go (`auto-update-go.yaml`)

**Trigger**: Daily at 10:00 AM UTC  
**Purpose**: Automatically update Go compiler version

**Manual trigger:**
```bash
gh workflow run auto-update-go.yaml
```

**What it does:**
1. Checks latest stable Go version from go.dev
2. Compares with current version in build.yaml
3. Updates build.yaml and Dockerfile.suse if newer version available
4. Creates PR with the updates
5. Triggers rebuild when merged

### 3. Auto-Update SUSE BCI (`auto-update-bci.yaml`)

**Trigger**: Daily at 12:00 PM UTC  
**Purpose**: Automatically update SUSE BCI base image

**Manual trigger:**
```bash
gh workflow run auto-update-bci.yaml
```

**What it does:**
1. Checks latest bci-micro digest from registry.suse.com
2. Compares with current digest in Dockerfile.suse
3. Updates Dockerfile.suse to pin new digest
4. Creates PR with the update
5. Triggers rebuild when merged

---

## Renovate (External Dependency Updates)

Go module dependencies are managed by [Renovate](https://docs.renovatebot.com/) (config: `renovate.json5`).

**Auto-merge enabled for:**
- Go module **patch** updates (e.g., 1.2.3 → 1.2.4)
- Security/vulnerability alerts (immediate, any time)
- GitHub Actions patch + minor updates

**Manual review required for:**
- Go module **minor** updates (grouped weekly)
- Go module **major** updates
- Anything Renovate flags as breaking

**Why Renovate (not Dependabot)?**
- Better grouping support
- More flexible auto-merge rules
- Vulnerability alerts work with auto-merge
- Already used in other Rancher repos

**Setup:** Install the Renovate GitHub app on this repo.

---

## Setup

### Prerequisites

1. Install GitHub CLI with agentic workflows extension:
   ```bash
   gh extension install github/gh-aw
   ```

2. Enable GitHub Agentic Workflows (technical preview) for the repository

### Compilation

Compile the markdown workflows to YAML:

```bash
# Compile all workflows
gh aw compile .github/workflows/cve-response.md
gh aw compile .github/workflows/weekly-health-check.md
gh aw compile .github/workflows/upstream-security-patch.md
```

This generates `.lock.yml` files (e.g., `cve-response.lock.yml`) which are the actual GitHub Actions workflows.

### Deployment

```bash
# Add and commit
git add .github/workflows/*.md
git add .github/workflows/*.lock.yml

git commit -m "feat: add agentic workflows for security automation"

git push origin rancher-main
```

## Security

All workflows use:
- **Read-only permissions** by default
- **Safe outputs** for creating PRs/issues (requires separate approval job)
- **Network allowlist** (GitHub API + common domains only)
- **Human review required** (PRs never auto-merge)

## Customization

To modify a workflow:

1. Edit the `.md` file (e.g., `cve-response.md`)
2. Recompile: `gh aw compile .github/workflows/cve-response.md`
3. Commit both `.md` and `.lock.yml` files

**Never edit `.lock.yml` files directly** - they are auto-generated.

## Testing

Test workflows manually:

```bash
# Trigger CVE response (comment on an issue)
gh issue comment 123 --body "/fix-cve"

# Trigger health check
gh workflow run weekly-health-check.md

# Trigger upstream patch scan
gh workflow run upstream-security-patch.md

# Watch execution
gh run watch
```

## Integration with rancher/image-scanning

The CVE response workflow is designed to integrate with the `rancher/image-scanning` repository.

When a CVE is detected in logging-operator images, the scanning repo should:
1. Create an issue in this repository
2. Label it with `cve/rancher-logging`
3. Maintainers can then comment `/fix-cve` to trigger automated fix creation

## References

- **GitHub Agentic Workflows Docs**: https://github.github.com/gh-aw/
- **Complete Guide**: See `docs/AGENTIC-WORKFLOWS-GUIDE.md` in ob-team-charts repo
- **Architecture**: See `docs/logging/fork/agentic-workflows.md` in ob-team-charts repo
