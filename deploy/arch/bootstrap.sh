#!/usr/bin/env bash
#
# tandem Arch bootstrap — the minimal ROOT-owned host foundation for a
# phone-first 007 workstation.
#
# Explicit mode is mandatory; there is no silent default and no default that
# mutates:
#
#     sudo ./deploy/arch/bootstrap.sh --check [--user NAME]   # read-only
#     sudo ./deploy/arch/bootstrap.sh --apply [--user NAME]   # mutating, idempotent
#
# --apply is idempotent by construction: it only installs packages whose marker
# binary is missing, uses `systemctl enable --now` / `loginctl enable-linger`
# (both idempotent), and `install -d` (create-if-absent). Running it twice makes
# no further changes. It also FAILS CLOSED: all host preconditions are checked
# before any mutation command runs.
#
# ---------------------------------------------------------------------------
# PROHIBITIONS — this script MUST NOT, and does NOT:
#   * run `tailscale up`, embed/accept a Tailscale auth key, edit ACLs, set DNS,
#     configure an exit node, or expose a Funnel;
#   * rewrite the firewall or open public ports;
#   * modify SSH authorized_keys, or generate/copy any private key;
#   * change the login shell of any user;
#   * install Claude/Codex credentials, or write OAuth/session files anywhere;
#   * migrate the host to NixOS, or install system-manager.
# Joining the tailnet (`tailscale up`) is a MANUAL operator step, on purpose.
# ---------------------------------------------------------------------------
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
user="tandem"
mode=""
# Overridable only for safe testing (defaults are the real host paths).
os_release="${TANDEM_OS_RELEASE:-/etc/os-release}"
unit_dir="${TANDEM_SYSTEMD_UNIT_DIR:-/usr/lib/systemd/system}"

die() {
  printf 'bootstrap: FAIL: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<EOF
usage:
  sudo $0 --check [--user NAME]   read-only host inspection (no changes)
  sudo $0 --apply [--user NAME]   install & enable the minimal host foundation

Exactly one of --check / --apply is required. The default is NEVER to mutate.
--user defaults to 'tandem'.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --check)
    mode="check"
    shift
    ;;
  --apply)
    mode="apply"
    shift
    ;;
  --user)
    user="${2:?--user needs a value}"
    shift 2
    ;;
  --user=*)
    user="${1#*=}"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "bootstrap: unknown argument: $1" >&2
    usage
    exit 2
    ;;
  esac
done

if [ -z "$mode" ]; then
  echo "bootstrap: no mode given — refusing to do anything (this is not an error you should silence)." >&2
  usage
  exit 2
fi

# --check delegates to the read-only host inspector (also CI-safe).
if [ "$mode" = "check" ]; then
  exec "$here/check-host.sh" --user "$user"
fi

# -------------------------------- --apply ----------------------------------
if [ "$(id -u)" -ne 0 ]; then
  die "--apply must run as root (use sudo)."
fi

# FAIL CLOSED: verify every host precondition BEFORE any mutation. Nothing below
# runs pacman / systemctl / loginctl / install until all of these pass.
assert_apply_preconditions() {
  [ -r "$os_release" ] || die "cannot read ${os_release}; refusing to mutate an unknown host"
  grep -qi '^ID=arch' "$os_release" || die "host is not Arch Linux (ID=arch required in ${os_release}); refusing to mutate"
  [ -d /run/systemd/system ] || die "systemd is not the active init; refusing to mutate"
  command -v pacman >/dev/null 2>&1 || die "pacman not found; refusing to mutate"
  command -v systemctl >/dev/null 2>&1 || die "systemctl not found; refusing to mutate"
  command -v loginctl >/dev/null 2>&1 || die "loginctl not found; refusing to mutate"
  getent passwd "$user" >/dev/null 2>&1 || die "target user '$user' does not exist; create it first (tandem never creates users)"
  [ -n "$(getent passwd "$user" | cut -d: -f6)" ] || die "cannot resolve home for '$user'; refusing to mutate"
}
assert_apply_preconditions

echo "bootstrap --apply: preconditions OK. target user = ${user}"
echo

# 1. Install missing required Arch packages. Idempotent: only packages whose
#    marker binary is absent are installed (so a Nix installed by other means is
#    respected, never reinstalled from pacman).
marker_present() {
  case "$1" in
  openssh) command -v sshd >/dev/null 2>&1 ;;
  tailscale) command -v tailscale >/dev/null 2>&1 ;;
  mosh) command -v mosh-server >/dev/null 2>&1 ;;
  nix) command -v nix >/dev/null 2>&1 ;;
  *) return 1 ;;
  esac
}

to_install=()
for pkg in openssh tailscale mosh nix; do
  if marker_present "$pkg"; then
    echo "  package ${pkg}: present, skipping"
  else
    to_install+=("$pkg")
  fi
done

if [ "${#to_install[@]}" -gt 0 ]; then
  echo "  installing: ${to_install[*]}"
  # No `-y` refresh / `-u` upgrade: tandem does not perform automatic Arch
  # upgrades. If the local package DB is too stale to resolve these, the
  # operator runs a full `pacman -Syu` (a change they control) and re-applies.
  if ! pacman -S --needed --noconfirm "${to_install[@]}"; then
    echo "  pacman could not install the required packages." >&2
    echo "  Your package DB may be stale. Run 'sudo pacman -Syu' (a system upgrade you" >&2
    echo "  control), then re-run: sudo $0 --apply --user ${user}" >&2
    exit 1
  fi
else
  echo "  all required packages already present"
fi

# 2. Establish the Nix daemon runtime. The Arch `nix` package SHIPS the systemd
#    units (nix-daemon.service + nix-daemon.socket) but, per Arch policy, does
#    NOT enable them on install. We standardize on the always-on service
#    (nix-daemon.service, WantedBy=multi-user.target) to avoid the socket-vs-
#    service bind conflict when a host may already run one. Idempotent.
echo
if [ ! -f "$unit_dir/nix-daemon.service" ]; then
  die "nix-daemon.service unit is missing from ${unit_dir}; is the Arch 'nix' package correctly installed?"
fi
if systemctl is-enabled nix-daemon.socket >/dev/null 2>&1; then
  # Host already uses socket activation — respect it, just make sure it runs.
  echo "  nix daemon: socket activation already enabled; ensuring active"
  systemctl start nix-daemon.socket
else
  echo "  nix daemon: enabling nix-daemon.service (enable --now)"
  systemctl enable --now nix-daemon.service
fi

# 3. Enable + start the two required system daemons. Idempotent.
echo
for unit in sshd tailscaled; do
  echo "  enabling ${unit} (enable --now)"
  systemctl enable --now "$unit"
done

# 4. Enable user lingering so tmux / the future o7d survive logout. Idempotent.
echo
echo "  enabling lingering for ${user}"
loginctl enable-linger "$user"

# 5. Create required user directories with correct ownership. Idempotent.
echo
home="$(getent passwd "$user" | cut -d: -f6)"
group="$(id -gn "$user")"
for d in "$home/.config" "$home/.local/state" "$home/.local/state/nix"; do
  echo "  ensuring dir ${d} (owner ${user}:${group})"
  install -d -o "$user" -g "$group" -m 0755 "$d"
done

echo
echo "bootstrap --apply: mutations complete. Verifying postconditions:"
echo
# Propagate the actual exit status: a hard FAIL from check-host (e.g. the target
# user cannot reach the Nix daemon) makes --apply fail. `set -e` aborts here on a
# nonzero exit, so the success banner below is only reached when postconditions
# hold. WARN-only results (e.g. flakes not yet persisted before the first deploy,
# or public-listener advisories) keep check-host at exit 0 and are not failures.
"$here/check-host.sh" --user "$user"

echo
echo "bootstrap --apply: done."

cat <<EOF

Nix daemon access & first deployment
  * No re-login is required for Nix: the Arch 'nix' package (verified with nix
    2.34.8-1) needs NO supplementary group — its daemon socket
    /nix/var/nix/daemon-socket/socket is mode 0666. We add no group, so there is
    nothing to re-login for. (The check reports actual connectivity, not a version.)
  * Test daemon access as ${user}:
        sudo -iu ${user} nix --extra-experimental-features nix-command \\
            store info --store daemon
  * FIRST Home Manager deployment (a clean Arch host has flakes DISABLED, so
    pass the features explicitly this one time):
        sudo -iu ${user} bash -lc 'cd /path/to/tandem && \\
            nix --extra-experimental-features "nix-command flakes" run .#deploy'
  * AFTER that activation, Home Manager owns ~/.config/nix/nix.conf, so the short
    forms work:  nix run .#check | .#deploy | .#rollback

MANUAL follow-ups — bootstrap deliberately does NOT do these:
  * Join the tailnet (interactive; no key is embedded):   sudo tailscale up
  * Review any non-loopback listeners printed above and your firewall policy by hand.
EOF
