{
  description = "jolt — Clojure on Chez Scheme";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Vendored git submodules
    irregex.url = "github:ashinn/irregex";
    irregex.flake = false;
    babashka-fs.url = "github:babashka/fs";
    babashka-fs.flake = false;
    babashka-process.url = "github:babashka/process";
    babashka-process.flake = false;
    sci.url = "github:borkdude/sci";
    sci.flake = false;
    clojure-test-suite.url = "github:jank-lang/clojure-test-suite";
    clojure-test-suite.flake = false;
  };

   outputs = { self, nixpkgs, irregex, babashka-fs, babashka-process, sci, clojure-test-suite }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkPackage = system:
        let
          pkgs = import nixpkgs { inherit system; };
          # Map nixpkgs system to Chez Scheme CSV machine directory
          chez-machine =
            if pkgs.stdenv.isDarwin then "tarm64osx"
            else if pkgs.stdenv.isx86_64 then "tlm64linux"
            else if pkgs.stdenv.isAarch64 then "tlm64linux"
            else throw "Unsupported system: ${system}";
          chez-csv = "${pkgs.chez}/lib/csv10.4.1/${chez-machine}";
          chez-wrapper = pkgs.writeShellScriptBin "chez" "exec ${pkgs.chez}/bin/scheme \"$@\"";

          # Copy source and symlink vendor/ submodules
          jolt-src = pkgs.stdenv.mkDerivation {
            name = "jolt-source";
            src = self.outPath;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out
              cp -r $src/* $out/
              # Create vendor directory with submodule symlinks
              mkdir -p $out/vendor
              ln -s ${irregex} $out/vendor/irregex
              ln -s ${babashka-fs} $out/vendor/fs
              ln -s ${babashka-process} $out/vendor/process
              ln -s ${sci} $out/vendor/sci
              ln -s ${clojure-test-suite} $out/vendor/clojure-test-suite
            '';
          };
        in
        pkgs.stdenv.mkDerivation {
          name = "jolt";
          version = "0.4.16";  # Update when tagging
          src = jolt-src;

          nativeBuildInputs = [ chez-wrapper pkgs.chez pkgs.gcc pkgs.git pkgs.unzip
                                pkgs.lz4.dev pkgs.zlib pkgs.ncurses pkgs.pkg-config
                                pkgs.xxd ];

          JOLT_CHEZ_CSV = chez-csv;
          JOLT_VERSION = "${pkgs.lib.fileContents "${self.outPath}/VERSION"}";

          buildPhase = ''
            make jolt-release
          '';

          installPhase = ''
            mkdir -p $out/bin $out/bin/lib
            cp target/release/jolt $out/bin/
            # Bundle nix store dylibs
            for lib in $(otool -L $out/bin/jolt | tail -n +2 | grep "/nix/store" | awk "{print \$1}"); do
              bn=$(basename $lib)
              cp $lib $out/bin/lib/$bn
              install_name_tool -change $lib @executable_path/lib/$bn $out/bin/jolt
            done
            # Fix transitive deps in bundled libs
            for bundled in $out/bin/lib/*; do
             for dep in $(otool -L $bundled | tail -n +2 | grep "/nix/store" | awk "{print \$1}"); do
                dbn=$(basename $dep)
                if [ ! -f $out/bin/lib/$dbn ]; then
                  cp $dep $out/bin/lib/$dbn
                fi
                install_name_tool -change $dep @executable_path/lib/$dbn $bundled
              done
            done
          '';

          doCheck = false;
        };

      mkDevShell = system:
        let
          pkgs = import nixpkgs { inherit system; };
          chez-wrapper = pkgs.writeShellScriptBin "chez" "exec ${pkgs.chez}/bin/scheme \"$@\"";
          chez-machine =
            if pkgs.stdenv.isDarwin then "tarm64osx"
            else if pkgs.stdenv.isx86_64 then "tlm64linux"
            else if pkgs.stdenv.isAarch64 then "tlm64linux"
            else throw "Unsupported system: ${system}";
          chez-csv = "${pkgs.chez}/lib/csv10.4.1/${chez-machine}";
        in
        pkgs.mkShell {
          name = "jolt-dev";

          buildInputs = [ chez-wrapper ] ++ (with pkgs; [
            chez
            gcc
            xxd
            git
            openssl
            unzip
            lz4.dev
            zlib
            ncurses
            pkg-config
            clojure
          ]);

          JOLT_CHEZ_CSV = chez-csv;
        };
    in
    {
      packages = forAllSystems (system: {
        default = mkPackage system;
      });

      devShells = forAllSystems (system: {
        default = mkDevShell system;
      });
    };
}
