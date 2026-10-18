{
  description = "cadmpeg - inspect and convert native CAD files (Fusion 360 .f3d, SolidWorks, STEP, ...)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        # The repo pins rustc/clippy in rust-toolchain.toml (currently 1.97.0).
        # Reading it here keeps the flake and CI on the same compiler without
        # having to wait for nixpkgs to ship that exact release.
        # Pinned here (matching rust-toolchain.toml) instead of reading that
        # file, so evaluation does not depend on it being in the flake source.
        rustToolchain = pkgs.rust-bin.stable."1.97.0".default.override {
          extensions = [ "rustfmt" "clippy" ];
        };

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

        cadmpeg = rustPlatform.buildRustPackage {
          pname = "cadmpeg";
          version = cargoToml.workspace.package.version;

          src = pkgs.lib.cleanSource ./.;

          # Cargo.lock has no git dependencies, so no outputHashes are needed.
          cargoLock.lockFile = ./Cargo.lock;

          # Build only the CLI (all codecs are on by default).
          cargoBuildFlags = [ "--package" "cadmpeg" ];

          # The workspace test suite produces 300MB-1.3GB test binaries and
          # needs corpus fixtures; run `cargo test-fast` in the dev shell
          # instead of inside the package build.
          doCheck = false;

          # zstd-sys compiles bundled C; stdenv already provides the compiler.
          nativeBuildInputs = [ pkgs.pkg-config ];

          # crates/cadmpeg/build.rs shells out to git to stamp the revision and
          # falls back to "unknown" when git/.git is absent (as in the sandbox).

          meta = with pkgs.lib; {
            description = "Inspect and convert native CAD files from the command line";
            homepage = "https://github.com/cadmpeg/cadmpeg";
            license = licenses.asl20;
            mainProgram = "cadmpeg";
            platforms = platforms.unix;
          };
        };
      in
      {
        packages = {
          inherit cadmpeg;
          default = cadmpeg;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = cadmpeg;
          name = "cadmpeg";
        };

        devShells.default = pkgs.mkShell {
          # git is needed by build.rs (revision stamp); the rest is the usual
          # Rust loop. The toolchain already includes rustfmt + clippy via
          # rust-toolchain.toml; rust-src/rust-analyzer are added for editors.
          packages = [
            (rustToolchain.override {
              extensions = [ "rustfmt" "clippy" "rust-src" "rust-analyzer" ];
            })
            pkgs.pkg-config
            pkgs.git
            pkgs.cargo-nextest
            pkgs.jq
            pkgs.python3
          ];

          RUST_BACKTRACE = "1";

          shellHook = ''
            echo "cadmpeg dev shell: $(rustc --version)"
            echo "  cargo build --workspace | cargo test-fast | cargo run -p cadmpeg -- --help"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;

        checks.build = cadmpeg;
      });
}