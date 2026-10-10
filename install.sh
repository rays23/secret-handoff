#!/usr/bin/env bash
# install.sh: write the depot config and install dset and dpush.
# Usage: install.sh DEPOT_PROJECT DEPOT_CONFIG
# Environment overrides (used by the tests): PREFIX (default ~/.local/bin), SECRET_HANDOFF_CONFIG.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local/bin}"
config="${SECRET_HANDOFF_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/secret-handoff/config}"

proj="${1:-}"
cfg="${2:-}"
re_id='^[a-z0-9][a-z0-9_-]*$'
if [[ $# -ne 2 || ! "$proj" =~ $re_id || ! "$cfg" =~ $re_id ]]; then
  echo "Usage: install.sh DEPOT_PROJECT DEPOT_CONFIG  (lowercase Doppler slugs)" >&2
  exit 1
fi

missing=()
for tool in doppler jq shasum pbpaste pbcopy; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if ((${#missing[@]} > 0)); then
  echo "Missing tools: ${missing[*]}. macOS with 'brew install dopplerhq/cli/doppler jq' covers them." >&2
  exit 1
fi

mkdir -p "$prefix" "$(dirname "$config")"
printf 'DEPOT_PROJECT=%s\nDEPOT_CONFIG=%s\n' "$proj" "$cfg" > "$config"
chmod 600 "$config"

for f in dset dpush handoff-lib.sh; do
  cp "$here/bin/$f" "$prefix/$f"
  chmod 755 "$prefix/$f"
done

echo "✓ Depot $proj/$cfg written to $config"
echo "✓ dset, dpush installed to $prefix"
case ":$PATH:" in
  *":$prefix:"*) ;;
  *) echo "! $prefix is not in PATH. Add: export PATH=\"$prefix:\$PATH\"" ;;
esac
