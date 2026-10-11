{
  description = "A startup basic project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    grove = {
      url = "git+file:///home/jinser/vie/projet/prototype/grove";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        devshell.follows = "devshell";
        flake-parts.follows = "flake-parts";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.devshell.flakeModule ];

      perSystem = { system, pkgs, ... }: {
        devshells.default = {
          packages =
            let
              pyEnv = pkgs.python3.withPackages (
                ps: with ps; [
                  brotli
                  fonttools
                ]
              );
            in
            [
              inputs.grove.packages.${system}.grove
              pyEnv
            ]
            ++ (with pkgs; [ ]);
        };
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    };
}
