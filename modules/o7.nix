{ o7pkg, ... }:
# Expose the pinned 007 product binary (`o7`) through the Home Manager profile.
#
# This module deploys the *product* built in PhysShell/007; tandem never patches
# or reimplements it. The exact revision is fixed by tandem's flake.lock and can
# be printed with `o7-revision` (see modules/workstation.nix).
#
# `o7d`, the future daemon, does NOT exist yet — nothing here pretends otherwise.
{
  home.packages = [ o7pkg ];
}
