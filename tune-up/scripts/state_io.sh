#!/usr/bin/env bash
# state_io.sh — atomic read/write helper for .claude/.tune-up-state.json.
#
# Usage:
#   state_io.sh read              -> prints snapshot JSON to stdout (or empty
#                                     default schema if the file is missing)
#   state_io.sh write <input.json> -> reads JSON from <input.json> and writes
#                                     it atomically to the state file
#   state_io.sh write -            -> same, but reads from stdin
#
# Operates relative to $CLAUDE_PROJECT_DIR (falls back to $PWD).
# Validates JSON before writing. Tempfile + rename so a crash can't corrupt
# the existing snapshot.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_DIR="${PROJECT_DIR}/.claude"
STATE_FILE="${STATE_DIR}/.tune-up-state.json"

# Pick a JSON validator. jq if present, else python3.
if command -v jq >/dev/null 2>&1; then
    json_validate() { jq -e . >/dev/null; }
elif command -v python3 >/dev/null 2>&1; then
    json_validate() { python3 -c 'import json,sys; json.load(sys.stdin)'; }
else
    echo "state_io.sh: need jq or python3 to validate JSON" >&2
    exit 2
fi

default_schema() {
    cat <<'EOF'
{
  "schema_version": 2,
  "last_run_iso": null,
  "local": {},
  "live": {},
  "upstream_at_last_run": {},
  "acknowledged_upstream_features": [],
  "pending_ansible_mirror": []
}
EOF
}

cmd_read() {
    local content
    # Single read; handle missing file via cat's exit. Trying-then-catching
    # avoids the test-then-read TOCTOU.
    if ! content="$(cat "${STATE_FILE}" 2>/dev/null)"; then
        default_schema
        return
    fi
    if ! printf '%s' "${content}" | json_validate; then
        echo "state_io.sh: ${STATE_FILE} is not valid JSON" >&2
        exit 3
    fi
    printf '%s' "${content}"
}

cmd_write() {
    local source="${1:-}"
    if [[ -z "${source}" ]]; then
        echo "state_io.sh: write needs a source path or '-' for stdin" >&2
        exit 2
    fi

    local input
    if [[ "${source}" == "-" ]]; then
        input="$(cat)"
    else
        if [[ ! -f "${source}" ]]; then
            echo "state_io.sh: source file not found: ${source}" >&2
            exit 2
        fi
        input="$(cat "${source}")"
    fi

    if [[ -z "${input}" ]]; then
        echo "state_io.sh: empty input, refusing to write" >&2
        exit 2
    fi

    if ! printf '%s' "${input}" | json_validate; then
        echo "state_io.sh: input is not valid JSON, refusing to write" >&2
        exit 3
    fi

    mkdir -p "${STATE_DIR}"

    # Atomic write: tempfile in the same directory (so rename is atomic on
    # the same filesystem), then rename over the target. Trap covers all
    # exit paths so an interrupted run doesn't leak the tempfile.
    local tmp
    tmp="$(mktemp "${STATE_DIR}/.tune-up-state.json.XXXXXX")"
    trap 'rm -f "${tmp}"' EXIT INT HUP TERM
    printf '%s\n' "${input}" >"${tmp}"
    mv -f "${tmp}" "${STATE_FILE}"
    trap - EXIT INT HUP TERM

    echo "state_io.sh: wrote ${STATE_FILE}" >&2
}

case "${1:-}" in
    read)  shift; cmd_read "$@" ;;
    write) shift; cmd_write "$@" ;;
    *)
        echo "Usage: state_io.sh {read | write <source|->}" >&2
        exit 2
        ;;
esac
