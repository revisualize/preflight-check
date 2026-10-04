# preflight-check

[![ci](https://github.com/revisualize/preflight-check/actions/workflows/ci.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/ci.yml)
[![test](https://github.com/revisualize/preflight-check/actions/workflows/test.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/test.yml)
[![shellcheck](https://github.com/revisualize/preflight-check/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/shellcheck.yml)
[![bash-compat](https://github.com/revisualize/preflight-check/actions/workflows/bash-compat.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/bash-compat.yml)
[![markdown-lint](https://github.com/revisualize/preflight-check/actions/workflows/markdown-lint.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/markdown-lint.yml)
[![links](https://github.com/revisualize/preflight-check/actions/workflows/links.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/links.yml)
[![content-policy](https://github.com/revisualize/preflight-check/actions/workflows/content-policy.yml/badge.svg)](https://github.com/revisualize/preflight-check/actions/workflows/content-policy.yml)
[![license: all rights reserved](https://img.shields.io/badge/license-all%20rights%20reserved-lightgrey)](LICENSE)

A manifest-driven environment checker that runs before real work does: required commands exist, paths are readable or writable, variables are set, disk has room, the clock is synced. Every failure is reported at once, in plain language, so a broken environment is a readable report instead of a mid-run mystery.

The manifest is the point. A file of assumptions sitting next to the script it protects is documentation that executes.

## The manifest

Plain text, one assumption per line. Comments and blank lines are ignored.

```text
# nightly_report.preflight
command    curl
command    jq
readable   /etc/nightly_report/config.json
writable   /var/lib/nightly_report
directory  /var/lib/nightly_report
variable   REPORT_RECIPIENT
disk_space /var/lib/nightly_report 500
clock_sync
```

| Directive | Arguments | Checks |
|-----------|-----------|--------|
| `command` | name | The command is on `PATH` |
| `readable` | path | The path exists and is readable |
| `writable` | path | The path is writable |
| `directory` | path | The path exists and is a directory |
| `variable` | name | The variable is set and non-empty |
| `disk_space` | path, megabytes | At least that many megabytes are free |
| `clock_sync` | none | The system clock is NTP synchronized |

## Usage

```sh
preflight_check.sh nightly_report.preflight
```

In front of a job, so it refuses to start in a broken world:

```sh
preflight_check.sh nightly_report.preflight || exit 1
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Every check passed |
| 1 | One or more checks failed |
| 2 | Manifest missing, unreadable, or malformed |

## Design notes

**Every failure is reported, then one exit.** Fix-rerun-fix-rerun against a checker that reveals one failure per run is a specific misery everyone has lived.

**An unverifiable check is a failed check.** If `clock_sync` is asked for and the host has neither `timedatectl` nor `chronyc`, the check fails with that explanation rather than skipping. If `disk_space` is asked for a path that cannot be stat'd, that is a failure, not a pass. A preflight that silently waives what it cannot verify converts the manifest from a contract into a suggestion.

**A malformed manifest is a loud error.** A directive with the wrong number of arguments, a non-numeric megabyte figure, or an unrecognized keyword exits 2. A directive that silently does nothing is a check you believe exists and do not have.

**The checker changes nothing.** No directory creation, no remediation. A preflight with side effects is a second thing to preflight.

## Known limitations

- The seven directives cover presence, not correctness. A dependency present at the wrong version, or a path writable but on the wrong filesystem, are outside the contract by design.
- `disk_space` requires GNU coreutils `df --output`. On BSD or busybox userlands it reports a hard failure rather than a wrong answer.
- Comment stripping removes everything after `#`, so paths containing that character cannot be expressed.

## Requirements

Bash 4.2 or newer, GNU coreutils. `timedatectl` or `chronyc` when `clock_sync` is used.

## Tests

```sh
bats test/
```

## Continuous integration

Each badge above is its own GitHub Actions workflow in `.github/workflows/`. Every workflow runs on each push and pull request, can be re-run by hand from the Actions tab, and links to its run history.

| Workflow | A green badge means |
|---|---|
| [`ci`](https://github.com/revisualize/preflight-check/actions/workflows/ci.yml) | `bash test/run_all_tests.sh` passed on Python 3.9 and 3.12 and reported a non-zero count of executed tests, and shellcheck found nothing at style severity. |
| [`test`](https://github.com/revisualize/preflight-check/actions/workflows/test.yml) | `bash test/run_all_tests.sh` passed on Python 3.9 and 3.12. The run fails if any suite fails or if zero tests executed, and the job summary lists each suite with its test count. |
| [`shellcheck`](https://github.com/revisualize/preflight-check/actions/workflows/shellcheck.yml) | Every shell script outside `test/fixtures/` parses with `bash -n` and has no shellcheck findings at style severity. |
| [`bash-compat`](https://github.com/revisualize/preflight-check/actions/workflows/bash-compat.yml) | The test suite passed under every Bash release from the floor stated in Requirements through 5.3, each built from its release source. |
| [`markdown-lint`](https://github.com/revisualize/preflight-check/actions/workflows/markdown-lint.yml) | Every Markdown file passes markdownlint. |
| [`links`](https://github.com/revisualize/preflight-check/actions/workflows/links.yml) | Every link in every Markdown file resolved on the latest run. It also runs weekly, because a link can break with no commit here. |
| [`content-policy`](https://github.com/revisualize/preflight-check/actions/workflows/content-policy.yml) | Every tracked file meets the publishing rules: UTF-8, LF line endings, no em dashes, scripts documented as `bash name.sh`, and vendor-neutral wording. |

A badge reports the latest run of those checks. What the tool needs on your own host is listed under Requirements.

## License

See [LICENSE](LICENSE). This code is published for viewing as a sample of the author's work. All rights reserved.
