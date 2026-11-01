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
      url = "github:jetjinser/grove";
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

      perSystem =
        { system, pkgs, lib, ... }:
        let
          grove = inputs.grove.packages.${system}.grove;
          floraGuileLibs = with pkgs; [ guile-json guile-lib ];
          guileEnv = [
            {
              name = "GUILE_LOAD_PATH";
              value = lib.concatStringsSep ":" (
                [ "${grove}/${pkgs.guile.siteDir}" grove.GUILE_LOAD_PATH ]
                ++ (map (p: "${p}/${pkgs.guile.siteDir}") floraGuileLibs)
              );
            }
            {
              name = "GUILE_LOAD_COMPILED_PATH";
              value = lib.concatStringsSep ":" (
                [ "${grove}/${pkgs.guile.siteCcacheDir}" grove.GUILE_COMPILED_PATH ]
                ++ (map (p: "${p}/${pkgs.guile.siteCcacheDir}") floraGuileLibs)
              );
            }
          ];
        in
        {
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
                grove
                pyEnv
              ]
              ++ (with pkgs; [
                gnumake
                guile
                poppler-utils
                imagemagick
                libavif
                curl
                reuse
              ])
              ++ floraGuileLibs;
            env = guileEnv;
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
