#!/usr/bin/env bash
#
# tandem rollback — roll the *user* Home Manager generation back by one.
# Refuses root. Fails closed when there is no prior generation. Never touches
# pacman packages, Tailscale state or root services.
#
# Invoked by `nix run .#rollback`, or directly.
set -euo pipefail

die() {
  printf 'rollback: FAIL: %s\n' "$*" >&2
  exit 1
}

# Refuse to run as root — this operates on a *user* profile only.
if [ "$(id -u)" -eq 0 ]; then
  die "refusing to run as root; rollback operates on the target user's Home Manager profile"
fi

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
