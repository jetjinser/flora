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

      perSystem =
        { system, pkgs, lib, ... }:
        let
          grove = inputs.grove.packages.${system}.grove;
          # Guile libraries Flora uses directly, beyond Grove's own set.
          floraGuileLibs = with pkgs; [ guile-json guile-lib ];
          # Mirror the Guile load paths grove bakes into its launcher so
          # plain `guile` invocations (make test, scripts) see the same
          # modules: grove's own site dir plus its Guile dependencies.
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
                poppler-utils # pdftoppm: rasterize the scanned PDF
                imagemagick # magick: crop figures from the pages
                libavif # avifenc: AVIF figure variants
                curl # fetch-fonts.sh and axe-core bootstrap
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
