# Security Policy

## Supported versions

| Version | Status |
|---|---|
| 2.12.x | Active, security fixes shipped within days of disclosure |
| Earlier than 2.12.x | **Unsupported**, upgrade to 2.12.x |

The 2.7.0 release (2026-04-29) closed a CVE-class arbitrary-code-execution sink in the `pp-sync` conf loader (`source` → strict parser). All earlier versions of `pp-sync` are vulnerable when run against a hand-edited or attacker-tampered project conf file. **Upgrade required.**

## What's in scope

| In scope | Out of scope |
|---|---|
| Code execution from a malicious project conf file (`~/.config/nq-pp-sync/projects/*.conf`) | Vulnerabilities in upstream `pac` CLI, `gh`, `glab`, or Power Pages itself |
| Path traversal / injection in `pp` subcommand inputs (project names, page names, solution names) | Privilege escalation outside the user's existing shell privileges |
| Credential / secret exposure in shipped scripts, documentation, or test fixtures | Network-level attacks against the user's PAC profile environment |
| Misuse of `gh` / `glab` against issues outside the current repo (cross-repo journal hijack) | Bugs in user-authored Liquid templates / Web API JS that the audit plugin merely reports on |
| `audit.py` parser misbehavior on adversarial portal source (crash, hang, false-positive escalation) | Decisions made by the LLM consuming the plugins (the plugin's job is to surface findings; act-on-findings is a user decision) |

## How to report

**Do not file public GitHub issues for vulnerabilities.** Instead, email `security@nerdyq.com` (or open a private security advisory at <https://github.com/Nerdy-Q/claude-power-pages-plugins/security/advisories/new>).

Include:
- A specific reproduction (a minimal conf file, fixture, or command sequence)
- The affected version (run `pp help | head -1` or check `versions.json`)
- The expected vs actual behavior
- Your assessment of impact (what can an attacker do that they shouldn't?)

You will receive an acknowledgement within 72 hours.

## What to expect after disclosure

| Severity | Initial response | Fix target |
|---|---|---|
| Critical (RCE, credential exfiltration) | within 24 hours | within 7 days |
| High (privilege escalation, data corruption) | within 72 hours | within 30 days |
| Medium (DoS, info disclosure) | within 1 week | next minor release |
| Low (hardening, defense-in-depth) | next monthly review | next minor release |

We will:
1. Confirm the report and reproduce the issue
2. Develop a fix and a regression test that pins the bug closed
3. Cut a patch release with a clear CVE-style note in the CHANGELOG
4. Credit the reporter (unless they prefer to remain anonymous)

## Security-relevant test surfaces

The marketplace ships **404 regression tests** across Python, bash, pac-mocked, journal-state, pac-contract, template-integration, design-system-knowledge, JSON-contract, performance-regression, metadata-consistency, and help-text-completeness coverage, including:
- conf-parser attack-vector fixtures for `pp-sync` (`$(...)`, backticks, env-var poisoning, control characters, literal-metachar resolution)
- URL-shape and same-repo enforcement tests for `pp journal note|close` (subdomain spoof, port injection, scheme downgrade, prefix confusion, path traversal)
- page-name validation tests for `pp generate-page` (path traversal, injection, shell metacharacters)
- atomic-registration tests for `pp project add` / `pp setup` (no partial conf writes on rejection)
- command-flow, install-script, pac-mocked, journal-state, pac-contract, and template-integration tests that exercise real CLI behavior beyond isolated parser rules

If you find a path through the parser, the URL validator, the page-name validator, or the registration flow that the existing tests don't cover, that's the highest-value report we can receive.

## What we don't accept

- **Theoretical issues without a reproducer.** "The CHANGELOG could be tampered with by an attacker who has write access to the repo" is not a vulnerability report.
- **Reports about the security of code the plugin generates.** The plugin's `pp generate-page` produces template code; if that template has a vulnerability, fix it in your portal source. Bugs in the *generator* are in scope; bugs in the *generated output* are your code.
- **AI-generated speculative reports.** If the report doesn't include a concrete reproducer that runs locally and demonstrates the vulnerability, we'll close it with a request for one.

## Existing closed disclosures

| Date | Severity | Issue | Fixed in |
|---|---|---|---|
| 2026-04-29 | Critical | `pp-sync` source-evaluated project conf files (any field was an RCE sink) | v2.7.0 (pp-sync 2.0.0, breaking change) |
| 2026-04-29 | High | `pp journal note\|close` could comment on / close arbitrary issues across any repo the maintainer has push access to (JOURNAL.md hijack via PR) | v2.7.0 |
| 2026-04-29 | High | `pp generate-page` page name flowed unchecked into filenames + heredocs (path traversal + YAML injection) | v2.7.3 |
| 2026-04-29 | Medium | `pp solution-down\|up` out-of-range pick crashed with bash `unbound variable` instead of friendly error | v2.7.3 |

The full audit history is in [`CHANGELOG.md`](CHANGELOG.md).
