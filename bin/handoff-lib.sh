#!/usr/bin/env bash
# Shared helpers for dset and dpush. Sourced, never executed.
# Compatible with bash 3.2 (macOS system bash).

HANDOFF_CONFIG_FILE="${SECRET_HANDOFF_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/secret-handoff/config}"

# Secret names: UPPER_SNAKE_CASE. Doppler project and config slugs: lowercase.
valid_name() { [[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]]; }
valid_id() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; }

# Resolve the depot (project and config where dset stores secrets).
# Order: environment variables DEPOT_PROJECT / DEPOT_CONFIG, then the config file.
# The config file is parsed line by line, never sourced, so it cannot run code.
load_depot() {
  local p="${DEPOT_PROJECT:-}" c="${DEPOT_CONFIG:-}" key val
  if { [[ -z "$p" ]] || [[ -z "$c" ]]; } && [[ -r "$HANDOFF_CONFIG_FILE" ]]; then
    while IFS='=' read -r key val || [[ -n "$key" ]]; do
      case "$key" in
        DEPOT_PROJECT) [[ -z "$p" ]] && p="$val" ;;
        DEPOT_CONFIG) [[ -z "$c" ]] && c="$val" ;;
      esac
    done < "$HANDOFF_CONFIG_FILE"
  fi
  if [[ -z "$p" || -z "$c" ]]; then
    echo "No depot configured. Run /secret-handoff:setup or write DEPOT_PROJECT and DEPOT_CONFIG to $HANDOFF_CONFIG_FILE" >&2
    return 1
  fi
  if ! valid_id "$p" || ! valid_id "$c"; then
    echo "Invalid depot '$p/$c'. Project and config must be lowercase Doppler slugs." >&2
    return 1
  fi
  DEPOT_PROJECT="$p"
  DEPOT_CONFIG="$c"
}

# SHA-256 of stdin, hex only.
sha() { shasum -a 256 | cut -d' ' -f1; }
