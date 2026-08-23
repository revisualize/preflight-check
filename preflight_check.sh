#!/usr/bin/env bash
#
# ---------------------------------------------------------------------
# Path:         preflight_check.sh
# Filename:     preflight_check.sh
# Project:      preflight_check
# Description:  Verify environment assumptions declared in a manifest.
#               Every failure is reported, then one exit.
# Status:       production
# Revision:     2
# Updated:      2026-08-05
# Requires:     Bash 4.2 or newer, GNU coreutils (df), and one of
#               timedatectl or chronyc when clock_sync is used
# Included by:  standalone command line tool; sourceable for testing
# Provides:     check_command_exists, check_path_readable,
#               check_path_writable, check_directory_exists,
#               check_variable_set, check_disk_space,
#               check_clock_synchronized, run_manifest
# ---------------------------------------------------------------------
#
# Portability
#   Target shells:  bash 4.2+ (uses arrays and indirect expansion).
#   Tested on:      bash 5.2 on Ubuntu 24.04.
#   df --output is GNU coreutils 8.21+ and is required. On BSD or
#   busybox userlands the disk_space directive will report a hard
#   failure rather than a wrong answer.
#
# Usage:
#   preflight_check.sh <manifest_file>
#
# Exit codes:
#   0  every check passed
#   1  one or more checks failed
#   2  manifest missing, unreadable, or malformed
#
# Environment:
#   PREFLIGHT_LIB_ONLY   set to 1 to source the functions for testing
#                        without executing a manifest
#

set -u

preflight_failure_messages=()
preflight_checks_run=0

add_failure() {
    preflight_failure_messages+=("${1}")
}

# ---------------------------------------------------------------------
# Individual checks. Each records failures; none exit on its own.
# ---------------------------------------------------------------------

check_command_exists() {
    command -v "${1}" > /dev/null 2>&1 \
        || add_failure "command not found in PATH: ${1}"
}

check_path_readable() {
    [ -r "${1}" ] || add_failure "not readable (missing or permissions): ${1}"
}

check_path_writable() {
    [ -w "${1}" ] || add_failure "not writable: ${1}"
}

check_directory_exists() {
    [ -d "${1}" ] || add_failure "not a directory: ${1}"
}

check_variable_set() {
    local variable_value
    variable_value="${!1:-}"
    [ -n "${variable_value}" ] || add_failure "variable unset or empty: ${1}"
}

# check_disk_space <path> <minimum_megabytes>
#
# An unverifiable check is a failed check. The previous implementation
# tested the exit status of a pipeline ending in tr, which succeeds even
# when df fails, so an unstattable path produced an empty reading, a
# silenced integer comparison error, and a PREFLIGHT OK verdict. The
# reading is now captured and validated before it is compared.
check_disk_space() {
    local target_path="${1}"
    local minimum_megabytes="${2}"
    local df_output
    local available_megabytes

    if ! df_output="$(df --output=avail --block-size=1M "${target_path}" 2>/dev/null)"; then
        add_failure "disk_space: cannot read free space for ${target_path} (path missing or df unsupported)"
        return
    fi

    available_megabytes="$(printf '%s\n' "${df_output}" | tail -n 1 | tr -d ' ')"

    if ! printf '%s' "${available_megabytes}" | grep -qE '^[0-9]+$'; then
        add_failure "disk_space: unreadable free-space value for ${target_path}"
        return
    fi

    if [ "${available_megabytes}" -lt "${minimum_megabytes}" ]; then
        add_failure "disk_space: ${target_path} has ${available_megabytes}MB free, need ${minimum_megabytes}MB"
    fi
}

check_clock_synchronized() {
    if command -v timedatectl > /dev/null 2>&1; then
        if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q '^yes$'; then
            return
        fi
        add_failure "clock_sync: timedatectl reports clock not NTP synchronized"
        return
    fi
    if command -v chronyc > /dev/null 2>&1; then
        if chronyc tracking 2>/dev/null | grep -q '^Leap status.*Normal'; then
            return
        fi
        add_failure "clock_sync: chronyc tracking does not report Normal leap status"
        return
    fi
    add_failure "clock_sync: no verification tool available (timedatectl, chronyc); unverifiable counts as failed"
}

# ---------------------------------------------------------------------
# Manifest handling
# ---------------------------------------------------------------------

# The manifest path is held here rather than passed into the loop body.
# ShellCheck pairs a `done < "${file}"` read against the same variable used
# beside a redirect inside the loop and reports SC2094; holding it once
# removes the pairing without weakening anything.
preflight_manifest_path=""

# manifest_error <line_number> <message>
# A malformed manifest is a loud error, never a skipped line. A directive
# that silently does nothing is a check you believe exists and does not.
manifest_error() {
    printf 'preflight_check: %s at %s line %d\n' \
        "${2}" "${preflight_manifest_path}" "${1}" >&2
    return 2
}

# run_manifest <manifest_file>
# Returns 0 all passed, 1 failures recorded, 2 malformed manifest.
run_manifest() {
    local manifest_file="${1}"
    local line_number=0
    local manifest_line
    local directive_name
    local first_argument
    local second_argument

    preflight_failure_messages=()
    preflight_checks_run=0
    preflight_manifest_path="${manifest_file}"

    if [ -z "${manifest_file}" ] || [ ! -r "${manifest_file}" ]; then
        printf 'usage: preflight_check.sh <manifest_file> (file must be readable)\n' >&2
        return 2
    fi

    while IFS= read -r manifest_line || [ -n "${manifest_line}" ]; do
        line_number=$((line_number + 1))
        manifest_line="${manifest_line%%#*}"
        read -r directive_name first_argument second_argument <<< "${manifest_line}" || true
        [ -z "${directive_name:-}" ] && continue
        preflight_checks_run=$((preflight_checks_run + 1))

        case "${directive_name}" in
            command|readable|writable|directory|variable)
                if [ -z "${first_argument:-}" ]; then
                    manifest_error "${line_number}" \
                        "directive \"${directive_name}\" requires one argument"
                    return 2
                fi
                ;;
            disk_space)
                if [ -z "${first_argument:-}" ] || [ -z "${second_argument:-}" ]; then
                    manifest_error "${line_number}" \
                        "directive \"disk_space\" requires a path and a minimum in megabytes"
                    return 2
                fi
                if ! printf '%s' "${second_argument}" | grep -qE '^[0-9]+$'; then
                    manifest_error "${line_number}" \
                        "disk_space minimum \"${second_argument}\" is not a whole number of megabytes"
                    return 2
                fi
                ;;
            clock_sync)
                if [ -n "${first_argument:-}" ]; then
                    manifest_error "${line_number}" \
                        "directive \"clock_sync\" takes no arguments"
                    return 2
                fi
                ;;
            *)
                manifest_error "${line_number}" \
                    "unknown directive \"${directive_name}\""
                return 2
                ;;
        esac

        case "${directive_name}" in
            command)    check_command_exists     "${first_argument}" ;;
            readable)   check_path_readable      "${first_argument}" ;;
            writable)   check_path_writable      "${first_argument}" ;;
            directory)  check_directory_exists   "${first_argument}" ;;
            variable)   check_variable_set       "${first_argument}" ;;
            disk_space) check_disk_space         "${first_argument}" "${second_argument}" ;;
            clock_sync) check_clock_synchronized ;;
        esac
    done < "${manifest_file}"

    [ "${#preflight_failure_messages[@]}" -gt 0 ] && return 1
    return 0
}

report_and_exit() {
    local manifest_file="${1}"
    local manifest_status="${2}"

    if [ "${manifest_status}" -eq 2 ]; then
        exit 2
    fi
    if [ "${manifest_status}" -eq 1 ]; then
        printf 'PREFLIGHT FAILED: %d of %d checks (%s)\n' \
            "${#preflight_failure_messages[@]}" "${preflight_checks_run}" "${manifest_file}"
        printf '  - %s\n' "${preflight_failure_messages[@]}"
        exit 1
    fi
    printf 'PREFLIGHT OK: %d checks passed (%s)\n' \
        "${preflight_checks_run}" "${manifest_file}"
    exit 0
}

if [ "${PREFLIGHT_LIB_ONLY:-0}" != "1" ]; then
    manifest_file_argument="${1:-}"
    run_manifest "${manifest_file_argument}"
    report_and_exit "${manifest_file_argument}" "$?"
fi
