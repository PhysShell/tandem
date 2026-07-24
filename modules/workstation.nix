{ pkgs, o7rev, ... }:
# Minimal user workstation toolset for a 1-core / 2-GB Arch VPS. Every entry
# here earns its place in a deployment/operations workflow — this is not a
# decorative CLI collection. Nothing here changes the login shell or touches
# root-owned configuration.
let
  # A tiny helper that prints the exact deployed 007 revision. Baked at build
  # time from the locked flake input (o7rev, threaded through from flake.nix),
  # so it can never drift from what is actually installed.
  o7-revision = pkgs.writeShellApplication {
    name = "o7-revision";
    runtimeInputs = [ ];
    text = ''
      # The deployed 007 revision, recorded from tandem's flake.lock at build.
      echo "${o7rev}"
    '';
  };
in
{
  home.packages = with pkgs; [
    # Version control + GitHub, the spine of the deployment workflow.
    git
    gh

    # Structured-data and search helpers the operator + docs rely on.
    jq
    ripgrep
    fd
    bat

    # Remote-access clients. tmux/mosh are configured in terminal.nix; the
    # packages themselves live here as the workstation toolset. openssh gives a
    # known-good `ssh` client for the plain-SSH fallback path.
    mosh
    openssh

    # Deployment shell helper: identify the exact running 007 build.
    o7-revision
  ];

  # Intentionally NOT managing ~/.gitconfig / ~/.ssh/config: those are operator-
  # owned on the VPS and managing them here risks clobbering real credentials
  # and identity. Home Manager owns the *tools*, not the operator's secrets.
}
