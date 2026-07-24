#!/usr/bin/env bash
#
# tandem rollback — roll the *user* Home Manager generation back by one.
# Enforces the operator identity contract (refuses root and any wrong user).
# Fails closed when there is no prior generation. Never touches pacman packages,
# Tailscale state or root services.
#
# Invoked by `nix run .#rollback` / `nix run .#rollback-staging`, or directly.
set -euo pipefail

TANDEM_CMD="rollback"

die() {
  printf 'rollback: FAIL: %s\n' "$*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=deploy/ops/identity.sh
. "$script_dir/identity.sh"

# Enforce identity BEFORE any profile inspection or rollback: refuses root and
# any user other than the bound target. Exits here on mismatch.
require_identity

profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager"

# Fail closed: no profile at all means nothing was ever deployed.
if [ ! -e "$profile" ]; then
  die "no Home Manager profile at ${profile}; nothing to roll back (deploy first)"
fi

# Fail closed: refuse when there is no prior generation to return to.
count="$(nix-env --profile "$profile" --list-generations | wc -l | tr -d ' ')"
if [ "$count" -lt 2 ]; then
  die "only ${count} generation(s) exist; no prior generation to roll back to"
fi

echo "rollback: available generations:"
nix-env --profile "$profile" --list-generations

echo
echo "rollback: rolling the user Home Manager profile back one generation…"
nix-env --profile "$profile" --rollback

# Activate the now-current (previous) generation. Default driver version leaves
# the profile pointer unchanged (old == new), so no new generation is created.
"$profile/activate"

echo
echo "rollback: done. selected generation:"
nix-env --profile "$profile" --list-generations | grep -E '\(current\)$' \
  || nix-env --profile "$profile" --list-generations | tail -n1
echo "rollback: pacman packages, Tailscale state and root services are untouched."
