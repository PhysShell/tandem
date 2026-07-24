#!/usr/bin/env bash
#
# tandem deploy — activate a Home Manager generation from the exact locked flake
# contents. User-scoped only; never touches root-owned Arch configuration.
#
# Invoked by `nix run .#deploy` (production) or `nix run .#deploy-staging`, which
# set the environment below, or directly with the same variables set.
#
#   TANDEM_FLAKE        path/URI of the locked flake (exact checked contents)
#   TANDEM_HM_NAME      home configuration name (e.g. tandem@tandem-vps)
#   TANDEM_TARGET_USER  OS user this command must run as
#   TANDEM_TARGET_HOME  that user's expected home
#   TANDEM_O7_REV       locked 007 revision (informational)
set -euo pipefail

TANDEM_CMD="deploy"

die() {
  printf 'deploy: FAIL: %s\n' "$*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=deploy/ops/identity.sh
. "$script_dir/identity.sh"

flake="${TANDEM_FLAKE:?TANDEM_FLAKE not set (run via: nix run .#deploy)}"
hm_name="${TANDEM_HM_NAME:-tandem@tandem-vps}"
o7_rev="${TANDEM_O7_REV:-unknown}"

# 1. Fail clearly on unsupported platform.
arch="$(uname -m)"
kernel="$(uname -s)"
if [ "$arch" != "x86_64" ] || [ "$kernel" != "Linux" ]; then
  die "unsupported platform ${kernel}/${arch}; tandem targets x86_64-linux"
fi

# 2. Enforce the operator identity contract BEFORE any build or activation:
#    refuses root, and requires the running user/home to match the target and
#    the selected HM output. Exits here on any mismatch.
require_identity

echo "deploy: building activation package for ${hm_name} from locked flake…"
echo "deploy: flake = ${flake}"
gen="$(nix build --no-link --print-out-paths \
  "${flake}#homeConfigurations.\"${hm_name}\".activationPackage")"

echo "deploy: activating ${gen}"
# Default driver version (0): the activation script registers the Home Manager
# profile generation itself, so `rollback` always has a prior generation.
"${gen}/activate"

echo
echo "deploy: done."
echo "deploy: deployed 007 revision : ${o7_rev}"
echo "deploy: activation package    : ${gen}"
echo "deploy: current generation:"
nix-env --profile "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager" \
  --list-generations | tail -n1
