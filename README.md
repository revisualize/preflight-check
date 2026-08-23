# preflight-check

![ci](https://github.com/revisualize/preflight-check/actions/workflows/ci.yml/badge.svg)

A manifest-driven environment checker that runs before real work does: required commands exist, paths are readable or writable, variables are set, disk has room, the clock is synced. Every failure is reported at once, in plain language, so a broken environment is a readable report instead of a mid-run mystery.

The manifest is the point. A file of assumptions sitting next to the script it protects is documentation that executes.

## The manifest

Plain text, one assumption per line. Comments and blank lines are ignored.

```
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

## License

See [LICENSE](LICENSE). This code is published for viewing as a sample of the author's work. All rights reserved.
