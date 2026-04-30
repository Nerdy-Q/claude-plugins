# pp-sync templates

Drop-in shell wrappers for `pac paportal` and `pac solution` workflows. Each script encodes the safety logic the bare `pac` commands lack, auth confirmation, env URL display, working-dir checks, bulk-upload warnings, post-flight smoke tests.

> **Most users want the `pp` CLI instead.** See [`../bin/pp`](../bin/pp) and [`../skills/pp-sync/references/cli-reference.md`](../skills/pp-sync/references/cli-reference.md). It uses a project registry (`~/.config/nq-pp-sync/projects/`) so `pp down anchor` works from anywhere, no per-project script copying. Run `~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-sync/<version>/install.sh` once, then `pp setup` to register projects.
>
> Use these standalone templates only when (a) you want wrappers committed to the project repo for teammates without `pp` installed, or (b) you're working a one-off project you don't want to register globally.

## Files

| Script | Purpose |
|---|---|
| `down.sh` | Download portal from Dataverse, auto-stash known noise |
| `up.sh` | Upload local changes to Dataverse, with bulk-upload warning |
| `doctor.sh` | Read-only health check (tooling, auth, structure) |
| `commit.sh` | Interactive selective commit |
| `solution-down.sh` | Export Dataverse solution + unpack into source-controllable form |
| `solution-up.sh` | Pack + import Dataverse solution (DESTRUCTIVE) |

## How to install in a new project

1. Copy the scripts you need to your project's repo root:
   ```bash
   PLUGIN_CACHE=~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-sync/<version>
   cp $PLUGIN_CACHE/templates/*.sh /path/to/your/repo/
   chmod +x /path/to/your/repo/*.sh
   ```

2. Edit the `CONFIG` block at the top of each script:
   ```bash
   # ============== CONFIG, set these per project ==============
   SITE_DIR="contoso---contoso"           # your site folder name
   PROFILE="modernization-dev"                                # your PAC auth profile
   WEBSITE_ID="00000000-0000-0000-0000-000000000000"  # from `pac paportal list`
   MODEL_VERSION="2"                                   # 1 = Standard, 2 = Enhanced
   ```

3. (Optional) Override defaults via environment variables instead of editing:
   ```bash
   SITE_DIR=my-site PROFILE=my-profile ./down.sh
   ```

4. (Optional) Add convenient aliases to your `.zshrc` / `.bashrc`:
   ```bash
   alias projdown='cd ~/Projects/MyProject && ./down.sh'
   alias projup='cd ~/Projects/MyProject && ./up.sh'
   alias projdoctor='cd ~/Projects/MyProject && ./doctor.sh'
   ```

## Per-project customization patterns

### Two-environment workflow (dev + client)

For projects deploying to a dev env and a client env from the same repo:

1. Copy each script twice with `-dev` and `-client` suffixes:
   ```bash
   cp down.sh down-dev.sh
   cp down.sh down-client.sh
   ```

2. Set different `PROFILE` and `SITE_DIR` values in each.

3. Some projects also use git branches as the deployment selector:
   ```bash
   # in the wrapper:
   BRANCH=$(git branch --show-current)
   case "$BRANCH" in
     main)        PROFILE=modernization-dev;        SITE_DIR=contoso---contoso ;;
     client-dev)  PROFILE=contoso-gov-client-dev; SITE_DIR=client-dev/contoso---contoso ;;
   esac
   ```

### Custom noise-cleanup rules

If your `down.sh` produces noise the default cleanup doesn't handle, extend the cleanup block. Examples:

```bash
# Strip volatile timestamps in YAML
find "$SITE_DIR" -name "*.yml" -exec sed -i '' -e 's/timestamp: .*/timestamp: <stripped>/' {} +

# Discard a specific noisy file every download
git checkout HEAD -- "$SITE_DIR/some-volatile-file.yml" 2>/dev/null || true
```

### Incremental upload by directory

For projects where bulk uploads consistently hang the cache, replace the `up.sh` upload block with a directory-by-directory loop:

```bash
for sub in basic-forms advanced-forms entity-lists web-templates web-files content-snippets web-pages page-templates table-permissions web-roles; do
  echo "=== $sub ==="
  pac paportal upload --path . --modelVersion 2 || break
  sleep 5  # let the cache warm up between batches
done
```

PAC doesn't natively support subset upload, so this is more conceptual than literal, production uses tend to git-stash everything else, upload, unstash next batch. Document the convention you settle on in your project's CLAUDE.md.

## What these scripts deliberately do NOT do

- **No `--no-verify` on `git commit`**, pre-commit hooks run. If a hook fails, fix the issue.
- **No `git reset --hard`**, too easy to lose local work. Use `git stash` instead.
- **No `pac admin delete`**, deleting environments is out of scope; do it via Admin Center where you can see what you're about to break.
- **No service principal auth flow**, these scripts assume interactive PAC profiles. SP auth is for CI/CD; use Microsoft's official patterns for that.
- **No untested cleanup**, the default noise-cleanup rules are conservative. Extend per-project if you have known-safe noise.

## License

MIT (same as the parent plugin)
