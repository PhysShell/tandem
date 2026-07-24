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

      # Identity of each deployment target. The Home Manager output name, the OS
      # user and its home are ONE unit — see modules + deploy/ops/identity.sh.
      targets = {
        production = {
          hmName = "tandem@tandem-vps";
          user = "tandem";
          home = "/home/tandem";
        };
        staging = {
          hmName = "tandem-staging@tandem-vps";
          user = "tandem-staging";
          home = "/home/tandem-staging";
        };
      };

      # One module set, two homes. Staging reuses the identical modules under a
      # different user/home so it validates the real configuration, not a copy.
      mkHome = { user, home, ... }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home/tandem-vps.nix
            {
              home.username = user;
              home.homeDirectory = home;
            }
          ];
          extraSpecialArgs = { inherit o7pkg o7rev; };
        };

      # Operator commands. The shell lives in reviewable, ShellCheck-able files
      # under deploy/ops/; each app is a thin wrapper that pins the flake path
      # (`${self}` = the exact locked flake contents) AND binds the target
      # identity (output name + OS user + home) so they can never be mixed.
      mkOp = { name, script, target }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ ];
          text = ''
            export TANDEM_FLAKE="${self}"
            export TANDEM_HM_NAME="${target.hmName}"
            export TANDEM_TARGET_USER="${target.user}"
            export TANDEM_TARGET_HOME="${target.home}"
            export TANDEM_O7_REV="${o7rev}"
            exec "${self}/deploy/ops/${script}" "$@"
          '';
        };

      ops = {
        deploy = mkOp { name = "deploy"; script = "deploy.sh"; target = targets.production; };
        check = mkOp { name = "check"; script = "check.sh"; target = targets.production; };
        rollback = mkOp { name = "rollback"; script = "rollback.sh"; target = targets.production; };
        deploy-staging = mkOp { name = "deploy-staging"; script = "deploy.sh"; target = targets.staging; };
        check-staging = mkOp { name = "check-staging"; script = "check.sh"; target = targets.staging; };
        rollback-staging = mkOp { name = "rollback-staging"; script = "rollback.sh"; target = targets.staging; };
      };

      mkApp = name: drv: { type = "app"; program = "${drv}/bin/${name}"; };

      # Formatter + linter resolved through THIS repo's locked nixpkgs, so the
      # result is determined by flake.lock, not the runner's registry.
      fmtCheck = pkgs.runCommand "check-nixpkgs-fmt" { nativeBuildInputs = [ pkgs.nixpkgs-fmt ]; } ''
        cd ${self}
        nixpkgs-fmt --check flake.nix home modules
        touch "$out"
      '';
      shellcheckCheck = pkgs.runCommand "check-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
        cd ${self}
        shopt -s globstar nullglob
        # Every shell script under deploy/ (ops, arch, ci, tests). `-x` follows
        # `source` directives so the sourced identity.sh lib is resolved.
        shellcheck -x deploy/**/*.sh
        touch "$out"
      '';
    in
    {
      # Standalone Home Manager configurations. Build with:
      #   nix build .#homeConfigurations."tandem@tandem-vps".activationPackage
      homeConfigurations = {
        "tandem@tandem-vps" = mkHome targets.production;
        # Staging: same modules, throwaway user. See docs/staging.md.
        "tandem-staging@tandem-vps" = mkHome targets.staging;
      };

      packages.${system} = {
        # The pinned product binary, exposed for inspection / CI resolution.
        o7 = o7pkg;
        default = o7pkg;
      } // ops;

      apps.${system} = builtins.mapAttrs mkApp ops;

      # Minimal shell for working *on* tandem itself (not deployed to the VPS).
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ git gh shellcheck nixpkgs-fmt ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;

      checks.${system} = {
        # Hermetic, locked-nixpkgs quality gates that `nix flake check` builds.
        fmt = fmtCheck;
        shellcheck = shellcheckCheck;
      } // ops; # building the wrappers also ShellChecks their generated text.
    };
}
