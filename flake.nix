# Copyright lowRISC Contributors.
# Licensed under the MIT License, see LICENSE for details.
# SPDX-License-Identifier: MIT
{
  description = "lowRISC CIC's Nix Packages and Environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  nixConfig = {
    extra-substituters = ["https://nix-cache.lowrisc.org/public/"];
    extra-trusted-public-keys = ["nix-cache.lowrisc.org-public-1:O6JLD0yXzaJDPiQW1meVu32JIDViuaPtGDfjlOopU7o="];
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    ...
  } @ inputs: let
    no_system_outputs = {
      lib = {
        poetryOverrides = import ./lib/poetryOverrides.nix;
        doc = import ./lib/doc.nix;
        buildFHSEnvOverlay = import ./lib/buildFHSEnvOverlay.nix;
      };
    };

    all_system_outputs = flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          rust-overlay.overlays.default
          (final: prev: {
            buildFHSEnvOverlay = final.callPackage no_system_outputs.lib.buildFHSEnvOverlay {};
          })
        ];
      };
      lowrisc_pkgs = import ./pkgs {inherit pkgs inputs;};
      opentitan = pkgs.callPackage ./dev/opentitan.nix {
        inherit (self.packages.${system}) ncurses5-fhs bazel_ot verilator_ot python_ot verible_ot;
      };
    in rec {
      checks = {
        license = pkgs.stdenv.mkDerivation {
          name = "license-check";
          src = ./.;
          dontBuild = true;
          doCheck = true;
          nativeBuildInputs = with pkgs; [reuse];
          checkPhase = ''
            reuse lint
          '';
          installPhase = ''
            mkdir $out
          '';
        };
      };
      packages = nixpkgs.lib.attrsets.mergeAttrsList [
        (flake-utils.lib.filterPackages system lowrisc_pkgs)
        {inherit opentitan;}
      ];
      devShells = {
        opentitan = opentitan.env;
        cheriot = pkgs.mkShell {
          name = "cheriot";
          packages =
            (with lowrisc_pkgs; [llvm_cheriot xmake])
            ++ (with pkgs; [
              gnumake
              magic-enum
              srecord
            ]);
        };
      };
      formatter = pkgs.alejandra;
    });
  in
    no_system_outputs // all_system_outputs;
}
