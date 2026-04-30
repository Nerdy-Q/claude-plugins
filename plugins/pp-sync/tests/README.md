# pp-sync test suites

Bash regression tests for `pp` CLI behavior. Twelve suites run in CI on every PR via `.github/workflows/plugin-validate.yml`.

## Suites

| File | Tests | What it verifies |
|---|---|---|
| `test_load_project.sh` | 22 | Strict key=value parser correctness. Includes attack-vector fixtures (`$(...)`, backticks, control chars, allowlist bypass attempts), literal-metachar project-resolution checks, parser edge cases (leading whitespace, only-comments, no-trailing-newline), the `$HOME` backward-compat expansion path, and v1-style conf migration rejection. |
| `test_register_atomic.sh` | 9 | `pp project add` atomicity. Rejected runs leave zero files behind; concurrent invocations against the same name converge to a single coherent conf (race-safe). |
| `test_journal_url_validation.sh` | 16 | `validate_issue_url_for_current_repo()` URL-shape regex + same-repo enforcement. Mocks `gh repo view` to test cross-repo hijack rejection without a real git checkout. Covers subdomain spoof, port injection, http downgrade, prefix confusion, path traversal, non-issue URLs, and 9 other attack vectors. |
| `test_command_flows.sh` | 86 | Happy-path and error-path coverage for command dispatch: project resolution, `show`, `list`, alias operations, project removal, switch/status, journal init, `generate-page` (incl. content correctness + JS/CSS placeholders), `sync-pages`, `setup` detection phase + full piped-stdin registration, and help output. |
| `test_subcommand_safety.sh` | 30 | Negative and edge-case coverage for subcommands beyond the parser: page-name traversal/injection rejection (incl. empty-slug rejection), solution-name CLI-arg validation, journal `Issue:` extraction invariants, solution-pick range validation, and doctor pipefail tolerance. |
| `test_install_script.sh` | 17 | Installer UX and safety: fresh install, idempotent re-run, non-symlink backup behavior, PATH guidance, installed `pp help` smoke check, and the upgrade path (symlink retargets when re-run from a new checkout location). |
| `test_pac_mocked.sh` | 23 | Mocked `pac` CLI flows in CI: doctor, switch/status, download/upload, solution export/import, validate-only upload, diff, and failure-injection paths without requiring a real tenant. |
| `test_journal_state.sh` | 10 | Journal active-issue state tracking and concurrency: state lifecycle, stale-state clearing, JOURNAL.md fallback, atomic concurrent opens, and project-remove cleanup. |
| `test_pac_contract.sh` | 10 | Contract assertions for what `pp` depends on from each `pac` subcommand. Runs in mock mode in CI and can run against real `pac` locally via `PP_PAC_REAL=1`. |
| `test_templates.sh` | 60 | End-to-end template coverage for `down.sh`, `up.sh`, `doctor.sh`, `solution-down.sh`, `solution-up.sh`, and `commit.sh` using mock `pac` plus audited invocation logs. Includes the BULK_THRESHOLD warning surface (cache-hang protection). |
| `test_help_completeness.sh` | 44 | Every command keyword dispatched in `bin/pp` must appear in `pp help`. Catches "added a command, forgot to document", parses the case-statement dispatch table separating top-level from `project`/`alias` sub-dispatchers. Also verifies every `cmd_*` function is reachable (no dead code). |
| `test_paths_with_spaces.sh` | 7 | `load_project`, `pp show`, `pp list`, and `pp doctor` correctly handle REPO/SITE_DIR paths containing spaces (e.g., `~/My Documents/portals/site---site`). Includes spaced filenames inside the site folder. |

Run any suite locally:

```bash
bash plugins/pp-sync/tests/test_load_project.sh
```

All suites set `PP_CONFIG_DIR` to a `mktemp -d` so they don't touch `~/.config/nq-pp-sync/`.

## Fixture conventions

`fixtures/*.conf` files exercise specific parser behaviors. Each fixture is named after the behavior it tests (e.g. `injection-via-repo.conf`, `path-poisoning.conf`).

When adding a fixture for command-injection or env-poisoning attacks, **also add a sentinel that proves the payload didn't execute**. Current convention: payloads `touch /tmp/pp-pwn-test-DO-NOT-EXECUTE` (or similar). Test runs assert the trap file does NOT exist after the suite.

## Source-safe `bin/pp`

The suites source `bin/pp` to access `load_project()` and `validate_issue_url_for_current_repo()` directly. `bin/pp` is structured to detect this:

```bash
return 2>/dev/null || main "$@"
```

When the file is sourced, `return` succeeds (we're inside a sourced script), so `main` is skipped. When executed, `return` errors and `main` runs. Tests therefore never accidentally dispatch a real command.

`PP_PROJECTS_DIR`, `PP_ALIASES_FILE`, and `PP_ACTIVE_FILE` are all overridable via `${VAR:-default}` so tests can isolate to a tmpdir without touching the user's real config.

## Adding a new test

1. **Decide which suite owns the behavior**:
   - Parser invariant → `test_load_project.sh`
   - Registration / file-write atomicity → `test_register_atomic.sh`
   - URL or external-system contract → `test_journal_url_validation.sh`
   - General subcommand flow / state behavior → `test_command_flows.sh`
   - Negative subcommand edge cases → `test_subcommand_safety.sh`
   - Brand-new behavior class → consider a new suite + a new CI step
2. **Add a fixture** (parser-style suites) or **inline stdin** (registration-style).
3. **Make the assertion specific**. Don't just check "exit code != 0" for an attack, assert what *actually* happened (e.g. trap file does NOT exist, conf file does NOT exist, allowlisted variable was NOT mutated).
4. Run locally, confirm it passes, push.

## Why bash and not pytest

The system under test is `bin/pp`, a ~1800-line bash script. Sourcing it from bash gives direct access to its functions and variables. Re-implementing the same harness in Python would need a subprocess shim that hides the very behavior we want to verify (function-table state, IFS handling, dynamic scoping), exactly the things that surface real bugs in shell code.

The Python suite (`audit.py`) tests Python code; the bash suites test bash code.

## Integration tests (`tests/integration/`)

A separate `integration/` subdirectory holds tests that exercise pp subcommands against a **real `pac` install + a registered project**. They are NOT wired into CI (the GitHub Actions runner has neither `pac` nor user projects).

Run locally:

```bash
bash plugins/pp-sync/tests/integration/test_pac_dependent.sh
```

What it checks (against the first registered project):
- `pp doctor`, full pac auth path; asserts every section runs to completion
- `pp diff`, git diff against site dir
- `pp up --validate-only`, pac validation without push
- `pp audit`, Python audit dispatch + JSON output parses
- `pp status`, active project + live env
- `pp solution-down`, real pac solution export + unpack against a Dataverse tenant (opt-in, see below)

The suite **auto-skips** if `pac` isn't installed or no projects are registered. To target a specific project:

```bash
PP_INTEGRATION_PROJECT=anchor bash tests/integration/test_pac_dependent.sh
```

### Live-tenant solution-down (opt-in)

`pp solution-down` is the one read-only-against-the-tenant operation that's worth exercising end-to-end before a release, it verifies real pac produces a usable zipfile shape (mocked tests cover shell orchestration but not Microsoft's actual export format). Opt in by naming the solution:

```bash
PP_INTEGRATION_PROJECT=anchor PP_INTEGRATION_SOLUTION_NAME=AnchorCore \
    bash tests/integration/test_pac_dependent.sh
```

Real export takes 60-120s and writes to the project's `$REPO/dataverse-schema/`. The test verifies `Other/Solution.xml` lands at the expected path and the zipfile is cleaned up after unpack.

### Destructive ops

Destructive operations (`pp down`, `pp up`, `pp solution-up`) are gated behind `PP_INTEGRATION_DESTRUCTIVE=1`. Even with that flag set, `pp solution-up` is permanently disabled by the suite, run it manually if you need to.

These integration tests are a smoke gate before each release. They prove the bash → pac → portal hand-off still works in practice; the in-CI unit tests prove the bash code is correct in isolation.
