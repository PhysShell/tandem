{ ... }:
# The tandem VPS workstation home. This is the single composition point; the
# username / homeDirectory are injected by the flake (production = `tandem`,
# staging = `tandem-staging`) so this file never hard-codes an identity.
{
  imports = [
    ../modules/workstation.nix
    ../modules/terminal.nix
    ../modules/o7.nix
  ];

  # Intentional, pinned state version. Home Manager uses it to keep stateful
  # defaults stable across upgrades; bumping it is a deliberate migration, never
  # an accident. Chosen at project start and left fixed on purpose.
  home.stateVersion = "25.05";

  # Let Home Manager manage its own installation so `nix run .#deploy` is the
  # only thing needed to keep the environment current.
  programs.home-manager.enable = true;
}
