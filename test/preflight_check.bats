#!/usr/bin/env bats
#
# ---------------------------------------------------------------------
# Path:         test/preflight_check.bats
# Filename:     preflight_check.bats
# Project:      preflight_check
# Description:  Behavioural tests for the manifest runner and each
#               individual check, including the silent-pass regressions.
# Status:       production
# Revision:     1
# Updated:      2026-08-05
# Requires:     bats, bash 4.2 or newer
# Included by:  .github/workflows/ci.yml
# Provides:     test coverage for preflight_check.sh
# ---------------------------------------------------------------------
#
# Run with:  bats test/
#

setup() {
  export PREFLIGHT_LIB_ONLY=1
  WORK="$(mktemp -d)"
  export WORK
  SCRIPT="${BATS_TEST_DIRNAME}/../preflight_check.sh"
  export SCRIPT
  source "${SCRIPT}"
}

teardown() {
  rm -rf "${WORK}"
}

write_manifest() {
  printf '%s\n' "$@" > "${WORK}/manifest"
  printf '%s' "${WORK}/manifest"
}

# ---------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------

@test "command directive passes for a command on PATH" {
  preflight_failure_messages=()
  check_command_exists bash
  [ "${#preflight_failure_messages[@]}" -eq 0 ]
}

@test "command directive fails for a command not on PATH" {
  preflight_failure_messages=()
  check_command_exists definitely_not_a_real_command
  [ "${#preflight_failure_messages[@]}" -eq 1 ]
}

@test "readable directive fails for a missing path" {
  preflight_failure_messages=()
  check_path_readable "${WORK}/absent"
  [ "${#preflight_failure_messages[@]}" -eq 1 ]
}

@test "writable directive passes for a writable directory" {
  preflight_failure_messages=()
  check_path_writable "${WORK}"
  [ "${#preflight_failure_messages[@]}" -eq 0 ]
}

@test "variable directive fails when the variable is empty" {
  preflight_failure_messages=()
  export PREFLIGHT_TEST_EMPTY=""
  check_variable_set PREFLIGHT_TEST_EMPTY
  [ "${#preflight_failure_messages[@]}" -eq 1 ]
}

@test "variable directive passes when the variable is set" {
  preflight_failure_messages=()
  export PREFLIGHT_TEST_SET="value"
  check_variable_set PREFLIGHT_TEST_SET
  [ "${#preflight_failure_messages[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------
# Regression: an unverifiable check must be a failed check
# ---------------------------------------------------------------------

@test "REGRESSION disk_space on a nonexistent path fails instead of passing" {
  preflight_failure_messages=()
  check_disk_space "/no/such/path/at/all" 500
  [ "${#preflight_failure_messages[@]}" -eq 1 ]
  [[ "${preflight_failure_messages[0]}" == *"cannot read free space"* ]]
}

@test "disk_space passes when free space exceeds the minimum" {
  preflight_failure_messages=()
  check_disk_space "${WORK}" 0
  [ "${#preflight_failure_messages[@]}" -eq 0 ]
}

@test "disk_space fails when free space is below an impossible minimum" {
  preflight_failure_messages=()
  check_disk_space "${WORK}" 999999999
  [ "${#preflight_failure_messages[@]}" -eq 1 ]
  [[ "${preflight_failure_messages[0]}" == *"need 999999999MB"* ]]
}

# ---------------------------------------------------------------------
# Regression: a malformed manifest is a loud error, not a skipped line
# ---------------------------------------------------------------------

@test "REGRESSION disk_space without a minimum is a manifest error, not a pass" {
  local manifest; manifest="$(write_manifest 'disk_space /tmp')"
  run run_manifest "${manifest}"
  [ "${status}" -eq 2 ]
}

@test "disk_space with a non-numeric minimum is a manifest error" {
  local manifest; manifest="$(write_manifest 'disk_space /tmp lots')"
  run run_manifest "${manifest}"
  [ "${status}" -eq 2 ]
}

@test "a directive missing its required argument is a manifest error" {
  local manifest; manifest="$(write_manifest 'command')"
  run run_manifest "${manifest}"
  [ "${status}" -eq 2 ]
}

@test "clock_sync with a stray argument is a manifest error" {
  local manifest; manifest="$(write_manifest 'clock_sync yes')"
  run run_manifest "${manifest}"
  [ "${status}" -eq 2 ]
}

@test "an unknown directive is a manifest error" {
  local manifest; manifest="$(write_manifest 'teleport /tmp')"
  run run_manifest "${manifest}"
  [ "${status}" -eq 2 ]
}

@test "a missing manifest file is a manifest error" {
  run run_manifest "${WORK}/no_such_manifest"
  [ "${status}" -eq 2 ]
}

# ---------------------------------------------------------------------
# Manifest runner behaviour
# ---------------------------------------------------------------------

@test "a fully satisfied manifest returns success" {
  local manifest; manifest="$(write_manifest 'command bash' "directory ${WORK}")"
  run run_manifest "${manifest}"
  [ "${status}" -eq 0 ]
}

@test "comments and blank lines are ignored and not counted as checks" {
  local manifest; manifest="$(write_manifest '# a comment' '' 'command bash')"
  run_manifest "${manifest}"
  [ "${preflight_checks_run}" -eq 1 ]
}

@test "every failure is reported, not just the first" {
  local manifest
  manifest="$(write_manifest 'command definitely_not_real_one' \
                             'command definitely_not_real_two' \
                             "readable ${WORK}/absent")"
  run_manifest "${manifest}" || true
  [ "${#preflight_failure_messages[@]}" -eq 3 ]
}

@test "a manifest with failures returns 1" {
  local manifest; manifest="$(write_manifest 'command definitely_not_real')"
  run run_manifest "${manifest}"
  [ "${status}" -eq 1 ]
}

@test "sourcing with PREFLIGHT_LIB_ONLY does not execute a manifest" {
  run bash -c "PREFLIGHT_LIB_ONLY=1 source '${SCRIPT}' && echo sourced_clean"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"sourced_clean"* ]]
}
