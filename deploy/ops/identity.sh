# shellcheck shell=bash
#
# tandem operator identity contract — sourced by deploy.sh / check.sh /
# rollback.sh. It refuses to proceed unless ALL of these agree, and never allows
# root to bypass it:
#
#   - the Home Manager output selected   TANDEM_HM_NAME  ("<user>@tandem-vps")
#   - the expected OS user               TANDEM_TARGET_USER
#   - the actually-running user          id -un
#   - the expected / real home           TANDEM_TARGET_HOME vs getent vs $HOME
#
# A mismatch fails BEFORE any build, activation, profile inspection or rollback.
# The (output, user, home) triple is bound by the flake wrapper, so an arbitrary
# caller cannot pair e.g. a production output with a staging user.

_tandem_id_fail() {
  printf '%s: FAIL: %s\n' "${TANDEM_CMD:-tandem}" "$*" >&2
  exit 1
}

require_identity() {
  local want_user want_home hm_user cur_uid cur_user ent_home

  want_user="${TANDEM_TARGET_USER:?TANDEM_TARGET_USER not set}"
  want_home="${TANDEM_TARGET_HOME:?TANDEM_TARGET_HOME not set}"
  : "${TANDEM_HM_NAME:?TANDEM_HM_NAME not set}"

  # The HM output name encodes its user as the "<user>@host" prefix. Bind it to
  # the target user so production-output + staging-user (or the reverse) is
  # rejected regardless of how the environment was assembled.
  hm_user="${TANDEM_HM_NAME%@*}"
  if [ "$hm_user" != "$want_user" ]; then
    _tandem_id_fail "output/user mismatch: HM output '${TANDEM_HM_NAME}' does not belong to target user '${want_user}'"
  fi

  # Never root — and root must not be a way around this contract.
  cur_uid="$(id -u)"
  if [ "$cur_uid" -eq 0 ]; then
    _tandem_id_fail "refusing to run as root; the operator identity contract must not be bypassed with root"
  fi

  # The running user must be exactly the target user.
  cur_user="$(id -un)"
  if [ "$cur_user" != "$want_user" ]; then
    _tandem_id_fail "identity mismatch: running as '${cur_user}', but this command targets '${want_user}'"
  fi

  # Resolve the authoritative home via getent and require it to agree with both
  # the declared home and the live HOME.
  ent_home="$(getent passwd "$want_user" 2>/dev/null | cut -d: -f6)"
  if [ -z "$ent_home" ]; then
    _tandem_id_fail "cannot resolve home for '${want_user}' via getent"
  fi
  if [ "$ent_home" != "$want_home" ]; then
    _tandem_id_fail "home mismatch: '${want_user}' resolves to '${ent_home}', configuration expects '${want_home}'"
  fi
  if [ "${HOME:-}" != "$ent_home" ]; then
    _tandem_id_fail "HOME mismatch: HOME='${HOME:-}' but '${want_user}' home is '${ent_home}'"
  fi

  # Verification-only stop: prove the identity gate without building or mutating
  # anything. Used by tests and by operators pre-flighting a deploy.
  if [ -n "${TANDEM_VERIFY_IDENTITY_ONLY:-}" ]; then
    printf '%s: identity OK — user=%s home=%s output=%s\n' \
      "${TANDEM_CMD:-tandem}" "$cur_user" "$ent_home" "$TANDEM_HM_NAME"
    exit 0
  fi
}
