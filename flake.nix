{
  description = "Dev shell with the GitHub CLI (gh)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.gh ];

          shellHook = ''
            echo "gh $(gh --version | head -n1 | awk '{print $3}') ready"
          '';
        };
      });

      packages = forAllSystems (pkgs: {
        default = pkgs.gh;
        gh = pkgs.gh;
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
