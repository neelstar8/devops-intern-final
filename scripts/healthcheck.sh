#!/bin/sh
# healthcheck.sh - assert that the NGINX app returns HTTP 200 on /healthz.
# Usage: ./scripts/healthcheck.sh [base-url]
# POSIX sh; no bashisms.
set -eu
# `pipefail` is not in POSIX sh, so enable it only when the shell supports it.
# shellcheck disable=SC3040
(set -o pipefail 2>/dev/null) && set -o pipefail

BASE_URL="${1:-http://localhost:8080}"
TARGET="${BASE_URL%/}/healthz"
TIMEOUT=5

if ! command -v curl >/dev/null 2>&1; then
    printf 'FAIL: curl is required but not installed\n' >&2
    exit 2
fi

printf 'Checking %s ...\n' "$TARGET"

# -s silent, -o capture body, -w print status, --max-time bound the request.
body_file=$(mktemp)
# Remove the temp file however the script exits.
trap 'rm -f "$body_file"' EXIT

if ! status=$(curl -s -o "$body_file" -w '%{http_code}' --max-time "$TIMEOUT" "$TARGET" 2>/dev/null); then
    printf 'FAIL: could not connect to %s\n' "$TARGET" >&2
    printf 'Diagnostic: the host refused the connection or timed out after %ss.\n' "$TIMEOUT" >&2
    printf '  - Is the container running?   docker ps\n' >&2
    printf '  - Is the port published?      docker port nginx-app\n' >&2
    exit 1
fi

if [ "$status" = "200" ]; then
    printf 'OK: %s returned HTTP 200\n' "$TARGET"
    printf 'Response body: %s\n' "$(cat "$body_file")"
    exit 0
fi

printf 'FAIL: %s returned HTTP %s (expected 200)\n' "$TARGET" "$status" >&2
printf 'Diagnostic: the endpoint answered but with an unexpected status.\n' >&2
printf '  - 404 means nginx.conf is missing the /healthz location block.\n' >&2
printf '  - 5xx means NGINX started but cannot serve; check: docker logs nginx-app\n' >&2
printf 'Response body: %s\n' "$(cat "$body_file")" >&2
exit 1
