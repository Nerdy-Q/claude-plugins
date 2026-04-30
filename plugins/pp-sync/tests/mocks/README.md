# Mock pac CLI

This directory contains a shell-script mock of the Microsoft Power Platform CLI (`pac`). It implements the subset of `pac` that `pp-sync` invokes, with realistic stdout shapes that `pp` parses against. State is held in a configurable directory so multiple invocations within a test interact coherently.

## Why a mock at all

`pp-sync` orchestrates `pac` for every sync, doctor, and solution operation. Real-world testing of those flows requires a Power Platform tenant + an authenticated PAC profile (see `tests/integration/test_pac_dependent.sh`). The mock lets the same flows be exercised in CI without any of that, deterministic, fast, no secrets needed.

## What's mocked

| `pac` subcommand | What the mock does |
|---|---|
| `pac auth list` | Prints registered profiles in the same tabular shape `pp` parses |
| `pac auth select --name X` | Marks `X` as selected; fails if `X` not in the profiles file |
| `pac auth create --name X --environment Y` | Registers `X` with URL `Y`, marks selected |
| `pac org who` | Prints the selected profile's URL in the format `pp` parses |
| `pac paportal list` | Prints two fake portals |
| `pac paportal download --path P --webSiteId G` | Creates a minimal `<P>/sample-site---sample-site/` skeleton |
| `pac paportal upload [--validateBeforeUpload]` | Echoes "Validation OK" or "Upload complete" |
| `pac solution export --path X` | Writes a stub zip (just the ZIP magic bytes) |
| `pac solution unpack --folder F` | Creates `F/Entities/` + `F/Other/Solution.xml` |
| `pac solution pack --zipfile Z` | Writes a stub zip |
| `pac solution import` | Echoes success |
| `pac --version` | Prints a mock version string |

## State directory

State persists in `$PP_MOCK_PAC_STATE_DIR` (default: `$HOME/.pp-mock-pac`). Tests should set this to a per-test `mktemp -d` so registrations don't leak between cases:

```bash
state=$(mktemp -d)
PATH="$mocks:$PATH" PP_MOCK_PAC_STATE_DIR="$state" pp doctor myproj
rm -rf "$state"
```

State files:
- `profiles`, one line per registered profile: `name=env_url`
- `selected`, currently selected profile name

To pre-populate a profile (skip the `auth create` step):

```bash
echo "myprof=https://acme-dev.crm.dynamics.com/" > "$state/profiles"
echo "myprof" > "$state/selected"
```

## Failure injection

Tests can force the mock to fail specific commands via env vars:

| Env var | Causes |
|---|---|
| `PP_MOCK_PAC_FAIL_AUTH_LIST=1` | `pac auth list` exits 1 with "Error: failed to read profile list" |
| `PP_MOCK_PAC_FAIL_AUTH_SELECT=1` | `pac auth select` exits 1 (e.g. simulated network failure) |
| `PP_MOCK_PAC_FAIL_ORG_WHO=1` | `pac org who` exits 1 with "No profile selected" |
| `PP_MOCK_PAC_FAIL_UPLOAD=1` | `pac paportal upload` exits 1 (validation or push failure) |
| `PP_MOCK_PAC_FAIL_SOLUTION_IMPORT=1` | `pac solution import` exits 1 (rejected by environment) |

This lets tests verify `pp`'s error-handling paths without contriving real auth failures.

## What's NOT mocked (yet)

- `pac auth delete`
- `pac auth update`
- `pac paportal create`
- `pac plugin*` subcommands
- Real solution validation (the mock's `solution import` always succeeds)

Add new subcommands to `pac` as new `cmd_<sub>_<action>()` functions and dispatch to them in `main()`.

## Why this is a shell script and not a Python tool

Same reason the test suites are bash: it runs on every machine that has bash, with no `pip install`. Tests that depend on the mock add no new dependencies to CI. The mock is ~355 lines (covers auth list/select/create, org who, paportal list/download/upload, solution export/unpack/pack/import, plus a `PP_MOCK_PAC_AUDIT_LOG` capture facility for assertion-friendly invocation tracing), short enough to read end-to-end before trusting.
