{ ... }:
# Persist the Nix experimental features the flake workflow needs, per user.
#
# The Arch `nix` package ships /etc/nix/nix.conf WITHOUT experimental features
# (verified against the pristine package: it contains only `build-users-group =
# nixbld`). So on a clean Arch host the FIRST deployment must pass the features
# explicitly:
#
#   nix --extra-experimental-features 'nix-command flakes' run .#deploy
#
# After that first activation, this module owns the USER config at
# ~/.config/nix/nix.conf so subsequent commands work as plain:
#
#   nix run .#check     nix run .#deploy     nix run .#rollback
#
# We do NOT rewrite the package-owned /etc/nix/nix.conf. Because this module is
# part of the shared set imported by home/tandem-vps.nix, production and staging
# receive identical feature configuration. No secrets belong in Nix config.
{
  xdg.configFile."nix/nix.conf".text = ''
    # Managed by tandem Home Manager (modules/nix.nix). Do not edit by hand.
    experimental-features = nix-command flakes
  '';
}
