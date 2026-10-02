#!/bin/sh
# sysinfo.sh - print basic host and Docker information for the assessment.
# POSIX sh; no bashisms.
set -eu
# `pipefail` is not in POSIX sh, so enable it only when the shell supports it.
# shellcheck disable=SC3040
(set -o pipefail 2>/dev/null) && set -o pipefail

section() {
    printf '\n== %s ==\n' "$1"
}

printf '================================\n'
printf ' System Information Report\n'
printf '================================\n'

section "Identity"
printf 'Current user   : %s\n' "$(id -un)"
printf 'Effective UID  : %s\n' "$(id -u)"
printf 'Hostname       : %s\n' "$(hostname)"

section "Kernel"
printf 'Kernel         : %s\n' "$(uname -srm)"

section "Date"
# ISO-8601 timestamp (UTC).
printf 'ISO date (UTC) : %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "Disk usage (root filesystem)"
df -h / 2>/dev/null || printf 'Disk usage unavailable\n'

section "Memory"
if command -v free >/dev/null 2>&1; then
    # Linux
    free -h
elif command -v vm_stat >/dev/null 2>&1; then
    # macOS has no `free`; report total RAM and free pages instead.
    total_bytes=$(sysctl -n hw.memsize)
    printf 'Total memory   : %s MB\n' "$((total_bytes / 1024 / 1024))"
    page_size=$(vm_stat | awk '/page size of/ {print $8}')
    free_pages=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
    printf 'Free memory    : %s MB\n' "$(( free_pages * page_size / 1024 / 1024 ))"
else
    printf 'Memory information unavailable on this platform\n'
fi

section "Docker daemon"
if ! command -v docker >/dev/null 2>&1; then
    printf 'Status         : docker CLI not installed\n'
elif docker info >/dev/null 2>&1; then
    printf 'Status         : running\n'
    printf 'Version        : %s\n' "$(docker version --format '{{.Server.Version}}')"
else
    printf 'Status         : installed but daemon not reachable\n'
fi

printf '\n'
