{
  description = "tandem — deployment & operations for a phone-first 007 workstation on Arch";

  inputs = {
    # nixpkgs drives Home Manager and the operator tooling. Home Manager follows
    # it so we resolve a single nixpkgs for the user profile.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The product. Pinned through flake.lock to an exact 007 revision; the
    # deployed `o7` binary comes from here and nowhere else.
    #
    # Deliberately NOT `follows`-ing our nixpkgs: 007 builds its Rust binary
    # against its own pinned nixpkgs (25.05) + crane + rust-overlay. Forcing our
    # unstable onto it would break its reproducible build. tandem consumes 007's
    # already-built package output, so the two nixpkgs never need to agree.
    o7 = {
      url = "github:PhysShell/007";
    };
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , o7
    }:
    let
      # This workstation is a single x86_64-linux Arch VPS. No cross-platform
      # abstraction — the extra systems would be dead weight nothing deploys to.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # The exact, locked 007 build. `o7.rev` is the revision recorded in
      # flake.lock, so it is the ground truth for "what is deployed".
      o7pkg = o7.packages.${system}.o7;
      o7rev = o7.rev or o7.sourceInfo.rev or "unknown";

      # One module set, two homes. Staging reuses the identical modules under a
      # different user/home so it validates the real configuration, not a copy.
      mkHome = { username, homeDirectory }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home/tandem-vps.nix
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ];
          extraSpecialArgs = { inherit o7pkg o7rev; };
        };

      # Operator commands. The shell lives in reviewable, ShellCheck-able files
      # under deploy/ops/; each app is a thin wrapper that pins the flake path
      # (`${self}` = the exact locked flake contents) and the target config.
      mkOp = { name, script, hmName ? "tandem@tandem-vps" }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ ];
          text = ''
            export TANDEM_FLAKE="${self}"
            export TANDEM_HM_NAME="${hmName}"
            export TANDEM_O7_REV="${o7rev}"
            exec "${self}/deploy/ops/${script}" "$@"
          '';
        };

      deployApp = mkOp { name = "deploy"; script = "deploy.sh"; };
      checkApp = mkOp { name = "check"; script = "check.sh"; };
      rollbackApp = mkOp { name = "rollback"; script = "rollback.sh"; };
    in
    {
      # Standalone Home Manager configurations. Build with:
      #   nix build .#homeConfigurations."tandem@tandem-vps".activationPackage
      homeConfigurations = {
        "tandem@tandem-vps" = mkHome {
          username = "tandem";
          homeDirectory = "/home/tandem";
        };
        # Staging: same modules, throwaway user. See docs/staging.md.
        "tandem-staging@tandem-vps" = mkHome {
          username = "tandem-staging";
          homeDirectory = "/home/tandem-staging";
        };
      };

      packages.${system} = {
        # The pinned product binary, exposed for inspection / CI resolution.
        o7 = o7pkg;
        default = o7pkg;

        # Operator commands, also available as packages for CI to build
        # (writeShellApplication runs ShellCheck at build time).
        deploy = deployApp;
        check = checkApp;
        rollback = rollbackApp;
      };

      apps.${system} = {
        deploy = {
          type = "app";
          program = "${deployApp}/bin/deploy";
        };
        check = {
          type = "app";
          program = "${checkApp}/bin/check";
        };
        rollback = {
          type = "app";
          program = "${rollbackApp}/bin/rollback";
        };
      };

      # Minimal shell for working *on* tandem itself (not deployed to the VPS).
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ git gh shellcheck nixpkgs-fmt ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;

      checks.${system} = {
        # Cheap, hermetic checks that `nix flake check` will build. The heavier
        # "activation package builds" is run explicitly in CI (see .github).
        deploy = deployApp;
        check = checkApp;
        rollback = rollbackApp;
      };
    };
}
