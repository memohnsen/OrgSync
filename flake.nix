{
  description = "OrgSync Apple development environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let system = "aarch64-darwin"; pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [ git just ruby_3_3 cocoapods xcbeautify ];
        shellHook = ''echo "Nix dev shell: OrgSync"'';
      };
    };
}
