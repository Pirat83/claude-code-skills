#!/usr/bin/env bash
# upstream_probe.sh — shell-side upstream probe for /tune-up Phase 1.
#
# Emits a JSON document on stdout:
#   {
#     "gh_releases":         [...]   # top 5 anthropics/claude-code GitHub releases
#                                     # (null if `gh` is unavailable / unauthenticated)
#     "marketplace_plugins": [...]   # sorted "<plugin>@<marketplace>" IDs
#     "installed_plugins":   [...]   # installed plugin entries (from claude CLI)
#     "known_marketplaces":  [...]   # marketplace metadata (lastUpdated etc.)
#   }
#
# Plugin enumeration prefers the canonical `claude plugin list --available
# --json` (returns both installed AND available, with rich metadata
# including scope/enabled/installPath/mcpServers). Falls back to walking
# ~/.claude/plugins/marketplaces/*/.claude-plugin/marketplace.json on disk
# if the `claude` CLI isn't available — that fallback only enumerates
# names, not metadata.
#
# Network: `gh release list` is the only network call. The script runs gh
# and the plugin probe in parallel via job control.

set -euo pipefail

PLUGINS_DIR="${HOME}/.claude/plugins"
MARKETPLACES_DIR="${PLUGINS_DIR}/marketplaces"
KNOWN_MARKETPLACES="${PLUGINS_DIR}/known_marketplaces.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "upstream_probe.sh: jq is required" >&2
    exit 2
fi

probe_dir="$(mktemp -d -t tune-up-probe.XXXXXX)"
trap 'rm -rf "${probe_dir}"' EXIT INT HUP TERM

# --- gh releases (top 5), in background ---------------------------------
probe_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo 'null' >"${probe_dir}/gh.json"
        return 0
    fi
    if ! gh release list --repo anthropics/claude-code -L 5 \
            --json tagName,publishedAt >"${probe_dir}/gh.json" 2>"${probe_dir}/gh.err"; then
        # Distinguish failure modes for the operator. The skill itself
        # treats null as "no upstream signal", but the stderr line lets a
        # human investigate.
        echo "upstream_probe.sh: gh release list failed (auth / rate limit / network):" >&2
        cat "${probe_dir}/gh.err" >&2
        echo 'null' >"${probe_dir}/gh.json"
    fi
}

# --- plugins (canonical CLI), in background -----------------------------
probe_plugins() {
    if command -v claude >/dev/null 2>&1; then
        if claude plugin list --available --json >"${probe_dir}/cpl.json" 2>"${probe_dir}/cpl.err"; then
            return 0
        fi
        echo "upstream_probe.sh: claude plugin list failed; falling back to disk walk:" >&2
        cat "${probe_dir}/cpl.err" >&2
    fi
    # Fallback: walk marketplace.json files on disk. Only available plugins
    # are enumerated; installed[] will be empty (caller can fill from
    # installed_plugins.json if needed).
    : >"${probe_dir}/cpl.json"
    if [[ -d "${MARKETPLACES_DIR}" ]]; then
        # -print0 + read -d '' handles newlines in filenames safely.
        local manifests=()
        while IFS= read -r -d '' manifest; do
            manifests+=("${manifest}")
        done < <(find "${MARKETPLACES_DIR}" -maxdepth 5 \
                      -path '*/.claude-plugin/marketplace.json' -print0 2>/dev/null)

        if (( ${#manifests[@]} > 0 )); then
            # Single jq invocation across all manifests.
            jq -n --slurpfile mfs <(jq -s . "${manifests[@]}") '
                {
                    installed: [],
                    available: [
                        $mfs[0][] as $m
                        | $m.plugins[]?
                        | { pluginId: "\(.name)@\($m.name)",
                            name: .name,
                            description: .description,
                            marketplaceName: $m.name,
                            source: .source }
                    ]
                }
            ' >"${probe_dir}/cpl.json"
        else
            echo '{"installed":[],"available":[]}' >"${probe_dir}/cpl.json"
        fi
    else
        echo '{"installed":[],"available":[]}' >"${probe_dir}/cpl.json"
    fi
}

probe_gh &
probe_plugins &
wait

# --- known marketplaces metadata (disk only) ----------------------------
known_marketplaces_json='[]'
if [[ -f "${KNOWN_MARKETPLACES}" ]]; then
    known_marketplaces_json="$(
        jq '[
              to_entries[]
              | { name: .key,
                  source: .value.source,
                  lastUpdated: .value.lastUpdated }
            ]' "${KNOWN_MARKETPLACES}"
    )"
fi

# --- compose output -----------------------------------------------------
jq -n \
    --slurpfile gh "${probe_dir}/gh.json" \
    --slurpfile cpl "${probe_dir}/cpl.json" \
    --argjson km "${known_marketplaces_json}" '
    {
        gh_releases: $gh[0],
        marketplace_plugins: ($cpl[0].available // [] | map(.pluginId) | sort | unique),
        installed_plugins: ($cpl[0].installed // []),
        known_marketplaces: $km
    }
'
