# Rancher Logging Operator Fork

SUSE-based fork of logging-operator with automated rebuilds and security workflows.

## Overview

This fork maintains a **frozen code version (4.10.0)** for stability while providing security updates through rebuilds.

We replace the upstream mirrored images with Rancher-built SUSE images that automatically rebuild when:
- New Go compiler releases are published (fixes stdlib CVEs)
- New SUSE BCI base images are available (fixes OS-level CVEs)
- Go module dependencies have security updates (fixes dependency CVEs)

**Security Model:**
- ✅ Security through fresh builds with updated dependencies
- ❌ We do NOT cherry-pick code changes from newer upstream versions
- ❌ Application code stays frozen at 4.10.0 for compatibility

## Branch Strategy

- **rancher-main** - Our main branch, forked from upstream `4.10.0` (code frozen)
- **auto-update-go-*** - Automated Go compiler update PRs
- **auto-update-suse-bci** - Automated SUSE BCI base image update PRs
- **auto-fix-cve-*** - Automated CVE fix PRs (build environment updates)

## Workflows

### Agentic Workflows (AI-Powered)

Located in `.github/workflows/*.md` - written in natural language, executed by AI agents.

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **cve-response.md** | `/fix-cve` slash command | Analyzes CVEs and creates PRs with build env updates |
| **weekly-health-check.md** | Mondays 6:57 AM UTC | Weekly repository and dependency health reports |

### Traditional Workflows (YAML)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **build.yaml** | Push/Tag/PR | Builds multi-arch SUSE images |
| **auto-update-go.yaml** | Daily 10:00 AM UTC | Updates Go compiler version |
| **auto-update-bci.yaml** | Daily 12:00 PM UTC | Updates SUSE BCI base image |

### Renovate (External)

Go module dependencies and GitHub Actions are managed by Renovate (`renovate.json5`):
- **Auto-merged**: patches, security alerts, GitHub Actions updates
- **Manual review**: minors (grouped weekly), majors

See [.github/workflows/README.md](.github/workflows/README.md#renovate-external-dependency-updates).

See [.github/workflows/README.md](.github/workflows/README.md) for detailed workflow documentation.

## Building

### Prerequisites

```bash
# Install goreleaser
brew install goreleaser  # macOS
# or follow: https://goreleaser.com/install/

# Verify installation
goreleaser --version
```

### Local Build

```bash
# Build with goreleaser (recommended)
./scripts/build.sh

# This will:
# 1. Build binaries for your architecture
# 2. Create Docker image using Dockerfile.suse
# 3. Tag as latest

# Custom repository name
GITHUB_REPOSITORY=myorg/logging-operator ./scripts/build.sh
```

### Manual Binary Build

```bash
# Build binary only (no Docker image)
CGO_ENABLED=0 go build \
  -ldflags="-s -w -X main.version=$(git describe --tags --always)" \
  -o logging-operator \
  ./main.go

# Then build image
cp logging-operator ./
docker build -f Dockerfile.suse -t logging-operator:latest .
```

### Multi-arch Release Build

```bash
# Tag a release
git tag -a v4.10.0-suse1 -m "Release v4.10.0-suse1"
git push origin v4.10.0-suse1

# Goreleaser will build multi-arch automatically in CI
# Or build locally:
GITHUB_REPOSITORY=manno/logging-operator goreleaser release --snapshot --clean
```

## Images

Built images are pushed to:
- **GHCR**: `ghcr.io/manno/logging-operator`
- **Tags**:
  - `latest` - Latest build from rancher-main
  - `<version>-suse1` - Release tags (e.g., `4.10.0-suse1`)
  - `dev-<commit>` - Development builds

## Build System

### Goreleaser

Production builds use [goreleaser](https://goreleaser.com/) for:
- ✅ Consistent builds across local/CI
- ✅ Multi-arch binary compilation
- ✅ Docker image creation with manifests
- ✅ Release artifact generation
- ✅ Better caching and iteration speed

Configuration: `.goreleaser.yaml`

### Dockerfile.suse

Simple SUSE BCI-based image that copies pre-built binaries:
- **Base**: `registry.suse.com/bci/bci-micro:latest`
- **User**: Non-root (65532:65532)
- **Binary**: Statically linked, stripped

The binary is built by goreleaser outside the container, then copied in. This pattern:
- Matches Rancher's existing build practices
- Enables better caching during development
- Allows binary reuse across multiple image variants
- Faster iteration compared to multi-stage builds

**Legacy multi-stage Dockerfile**: `Dockerfile.suse.multistage` (kept for reference)

## Security

### Security Model

**We maintain a frozen code version (4.10.0)** to avoid breaking changes for Rancher users.

Security comes from **rebuilding** with updated build environment:
- **Go compiler updates** → Fix Go stdlib CVEs
- **SUSE BCI updates** → Fix OS-level CVEs  
- **Go module updates** → Fix dependency CVEs

We do NOT cherry-pick code changes from upstream newer versions.

### Automated CVE Response

When a CVE is detected by the security team's image-scanning repository:

1. Image-scanning repo creates a CVE issue in their repo (not mirrored to ours)
2. Image-scanning repo triggers our workflow:
   ```bash
   gh workflow run cve-response \
     --repo manno/logging-operator \
     -f issue_url=<url-of-cve-issue>
   ```
3. AI agent fetches the remote CVE issue and analyzes it
4. Agent determines which build component needs updating (Go/BCI/module)
5. Agent creates a PR updating Go compiler / SUSE BCI / Go module
6. Agent comments back on the original CVE issue with the PR link
7. Rebuilding with updated environment fixes the CVE
8. Security team reviews PR and merges
9. New image is built and available for re-scanning

### Renovate (Go Module Updates)

[Renovate](https://docs.renovatebot.com/) handles Go module security updates with auto-merge:
- **Vulnerability alerts**: Auto-merged immediately (any time)
- **Patch updates**: Auto-merged after CI passes
- **Minor updates**: Grouped weekly, require review
- **Major updates**: Always require review

Configuration: `renovate.json5`

### Automated Dependency Updates

Automated daily checks for:
- Go compiler updates (10:00 AM UTC)
- SUSE BCI base image updates (12:00 PM UTC)

Updates create PRs automatically for review.

## Development

### Prerequisites

```bash
# Docker with buildx
docker buildx version

# GitHub CLI (for workflows)
gh --version

# jq (for JSON parsing)
jq --version
```

### Testing Workflows

```bash
# Trigger manual builds
gh workflow run build.yaml

# Trigger Go update check
gh workflow run auto-update-go.yaml

# Trigger BCI update check
gh workflow run auto-update-bci.yaml

# Watch workflow execution
gh run watch

# View logs
gh run view --log
```

### Agentic Workflow Development

See [.github/workflows/README.md](.github/workflows/README.md) for:
- How to modify agentic workflows
- Compilation with `gh aw compile`
- Testing agentic workflows

## Integration with ob-team-charts

Each push to `rancher-main` that produces a new image automatically dispatches an
`image-updated` event to `manno/ob-team-charts`. The `image-update.yaml` workflow
there resets the `auto/rancher-logging-suse-updates` branch, updates
`packages/rancher-logging/4.10/generated-changes/patch/values.yaml.patch`, and
opens/updates a PR targeting `rancher-logging-4.10-suse1`.

The current rendered chart is `4.10.0-rancher.30-suse1` with this image:
```yaml
# values.yaml.patch (logging-operator entry)
image:
  repository: ghcr.io/manno/logging-operator
  tag: dev-775aefe4
```

`CHARTS_DISPATCH_TOKEN` must be set as a repo secret — a fine-grained PAT with
**Contents: write** on `manno/ob-team-charts`.

## Upstream Relationship

- **Upstream**: https://github.com/kube-logging/logging-operator
- **Fork point**: v4.10.0 (code frozen at this version)
- **Sync strategy**: None - we do NOT sync code changes from upstream
- **Security strategy**: Rebuild with fresh dependencies, not upstream patches
- **Rationale**: Maintain compatibility for Rancher users while fixing CVEs through build updates

## Contributing

### Creating PRs

All PRs should:
- Target the `rancher-main` branch
- Include tests if modifying code
- Update documentation if needed
- Follow conventional commit format

### Automated PRs

Many PRs are created automatically by workflows. These should be:
- Reviewed for correctness
- Tested before merging
- Merged promptly if valid (to trigger rebuilds)

## Troubleshooting

### Build Fails

```bash
# Check Go version compatibility
grep GO_VERSION Dockerfile.suse .github/workflows/build.yaml

# Verify base image
docker pull registry.suse.com/bci/bci-micro:latest

# Test local build
./scripts/build.sh
```

### Workflow Not Triggering

```bash
# Check workflow is enabled
gh workflow list

# Enable if disabled
gh workflow enable <workflow-name>

# View recent runs
gh run list --workflow=<workflow-name>
```

### Agentic Workflow Issues

See the [troubleshooting section](.github/workflows/README.md#troubleshooting) in the workflows README.

## References

- **POC Guide**: `docs/logging/fork/poc.md` in ob-team-charts repo
- **Agentic Workflows Guide**: `docs/AGENTIC-WORKFLOWS-GUIDE.md` in ob-team-charts repo
- **Architecture**: `docs/logging/fork/agentic-workflows.md` in ob-team-charts repo
- **Upstream Docs**: https://kube-logging.dev/
