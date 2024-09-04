# Copyright lowRISC contributors.
#
# SPDX-License-Identifier: MIT
{
  pkgs,
  ncurses5-fhs,
  bazel_ot,
  python_ot,
  verilator_ot,
  verible_ot,
  edaTools ? [],
  wrapCCWith,
  gcc-unwrapped,
  pkg-config,
  extraPkgs ? [],
  ...
}: let
  # These dependencies are required for building user DPI C/C++ code, and cosimulation models.
  edaExtraDeps = with pkgs; [elfutils openssl python_ot];

  # Bazel rules_rust expects build PIE binary in opt build but doesn't request PIE/PIC, so force PIC
  gcc-patched = wrapCCWith {
    cc = gcc-unwrapped;
    nixSupport.cc-cflags = ["-fPIC"];
  };

  # Bazel filters out all environment including PKG_CONFIG_PATH. Append this inside wrapper.
  pkg-config-patched = pkg-config.override {
    extraBuildCommands = ''
      echo "export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/lib/pkgconfig" >> $out/nix-support/utils.bash
    '';
  };
in
  (pkgs.buildFHSEnvOverlay {
    pname = "opentitan";
    version = "dev";
    targetPkgs = _:
      with pkgs;
        [
          bazel_ot
          python_ot
          verilator_ot
          verible_ot

          # For serde-annotate which can be built with just cargo
          rustup

          # For the OTBN simulator
          ninja

          # dvsim uses git for logging/tagging purposes
          git

          # Bazel downloads Rust compilers which are not patchelfed and they need this.
          zlib
          openssl
          curl
          util-linux # flock for bazelisk

          gcc-patched
          pkg-config-patched

          libxcrypt-legacy
          udev
          libftdi1
          libusb1 # needed for libftdi1 pkg-config
          ncurses5-fhs

          srecord

          # For documentation
          hugo
          doxygen
          libxslt # util/mdbook/difgen.py, requires `xsltproc` to be in the path.
        ]
        # Binaries generated by the EDA tools do no have RPATH set so they also need runtime deps.
        ++ edaExtraDeps
        # EDA tools are themselves wrapped inside a FHS env, which recreates FHS paths (/bin, /lib, ...) afresh.
        # This means that they can't see tools added to FHS paths in this "opentitan" env.
        # As a workaround, pass these dependencies as an `extraDependencies` arg into them.
        ++ map (tool:
          tool.override {
            extraDependencies = edaExtraDeps;
          })
        edaTools
        ++ extraPkgs;
    extraOutputsToInstall = ["dev"];

    profile = ''
      # Workaround bazel bug: https://github.com/bazelbuild/bazel/issues/23217
      export TMPDIR=/tmp
    '';

    runScript = "\${SHELL:-bash}";
  })
  .env
