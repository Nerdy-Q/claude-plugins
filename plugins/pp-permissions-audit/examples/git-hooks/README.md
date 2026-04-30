# Power Pages permissions audit: git pre-commit hook

A drop-in pre-commit hook that runs `pp-permissions-audit` against your Power Pages site folder on every commit and **blocks the commit on ERROR-class findings**.

## What it does

- Auto-detects the site folder (the first `<name>---<name>/` containing `website.yml` + `web-pages/`)
- Runs `audit.py --severity ERROR --exit-code` against it
- Blocks the commit if there are any ERROR-class findings (Web API enabled with no permission, orphaned permissions, anonymous-role writes, etc.)
- No-op on non-Power-Pages repos, safe to install globally via `core.hooksPath`

ERROR-class findings indicate **definite** security or runtime bugs. WARN and INFO findings are not gated by the hook (they're informational; surface them in CI for review).

## Install

From the root of your Power Pages project's git repo:

```bash
~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-permissions-audit/<version>/examples/git-hooks/install-hook.sh
```

The installer:

1. Verifies cwd is a git repo
2. Backs up any existing `.git/hooks/pre-commit` to `.pre-commit.bak.<timestamp>`
3. Symlinks (preferred) or copies the template into `.git/hooks/pre-commit`
4. `chmod +x` the result

Test the install without committing real work:

```bash
git commit --allow-empty -m 'test pp-audit hook'
```

## Bypass

```bash
git commit --no-verify
```

**Caveat:** `--no-verify` skips the hook locally, but the GitHub Actions / Azure Pipelines gate (see [`../github-actions/power-pages-audit.yml`](../github-actions/power-pages-audit.yml)) will still fail on push/PR. Use sparingly.

## Uninstall

```bash
rm .git/hooks/pre-commit
# Optional: restore a backup written by install-hook.sh
mv .git/hooks/pre-commit.bak.<timestamp> .git/hooks/pre-commit
```

## Why both pre-commit and CI?

- **Pre-commit (this hook)**, fast, local feedback **before push**. Catches issues at the earliest possible point. Bypassable.
- **CI (`examples/github-actions/power-pages-audit.yml`)**, runs on the remote, **non-bypassable** for PRs. Source of truth.

The pre-commit hook saves a CI round-trip when you'd otherwise be told to fix something obvious. CI is the gate that actually decides whether code merges.

## Using the [pre-commit framework](https://pre-commit.com)?

If you already use the `pre-commit` framework in your repo, this hook script is **not** the right shape, the framework expects hooks declared in `.pre-commit-config.yaml` with a specific entry point and `language` setting. A snippet like:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: pp-permissions-audit
        name: Power Pages permissions audit
        entry: bash -c 'SITE_DIR=$(find . -maxdepth 6 -type d -name "*---*" | while read d; do [ -f "$d/website.yml" ] && [ -d "$d/web-pages" ] && echo "$d" && break; done); SCRIPT=$(find ~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-permissions-audit ~/.claude/plugins/cache/nq-claude-plugins/pp-permissions-audit -path "*/scripts/audit.py" 2>/dev/null | sort -V | tail -1); python3 "$SCRIPT" "$SITE_DIR" --severity ERROR --exit-code'
        language: system
        pass_filenames: false
        always_run: true
```

is the right starting point. (The framework runs hooks in its own venv; `language: system` lets us shell out to the bundled `audit.py`.) For most teams, the standalone `.git/hooks/pre-commit` install via `install-hook.sh` is simpler, pick whichever matches your existing workflow.
