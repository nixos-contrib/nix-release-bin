{
  description = "Install the binaries a GitHub release published, instead of building from source";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    {
      lib.mkReleaseBin = import ./lib.nix;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        mkReleaseBin = import ./lib.nix;
        fallback = pkgs.writeShellScriptBin "fallback" "" // {
          meta.description = "fallback";
        };
        # Real releases, which the binary checks fetch and run: one whose Linux
        # binary is static, and one whose Linux binary loads glibc and libgcc.
        releases = [
          "protoc-gen-go-aip"
          "protoc-gen-rust-aip"
        ];
        pinned =
          name:
          builtins.hasAttr system (builtins.fromJSON (builtins.readFile ./tests/fixture/${name}.json)).assets;

        failures = pkgs.lib.runTests {
          testFallsBackWithoutABinary = {
            expr =
              (mkReleaseBin {
                inherit pkgs fallback;
                pname = "example-app";
                manifest = {
                  version = "1.0.0";
                  assets = { };
                };
              }).name;
            expected = fallback.name;
          };
          testFailsWithoutABinaryOrFallback = {
            expr =
              (builtins.tryEval
                (mkReleaseBin {
                  inherit pkgs;
                  pname = "example-app";
                  manifest = {
                    version = "1.0.0";
                    assets = { };
                  };
                }).name
              ).success;
            expected = false;
          };
          testPackagesTheBinary = {
            expr =
              let
                binary = mkReleaseBin {
                  inherit pkgs fallback;
                  pname = "example-app";
                  manifest = {
                    version = "1.0.0";
                    assets.${system} = {
                      url = "https://example.com/example-app-${system}";
                      hash = pkgs.lib.fakeHash;
                    };
                  };
                };
              in
              {
                inherit (binary) name;
                inherit (binary.meta) description mainProgram platforms;
              };
            expected = {
              name = "example-app-1.0.0";
              description = "fallback";
              mainProgram = "example-app";
              platforms = [ system ];
            };
          };
        };
      in
      {
        checks = {
          lib =
            if failures == [ ] then
              pkgs.runCommand "lib-tests" { } "touch $out"
            else
              throw "lib.nix tests failed: ${builtins.toJSON failures}";
        }
        // builtins.listToAttrs (
          map (name: {
            name = "binary-${name}";
            value =
              let
                binary = mkReleaseBin {
                  inherit pkgs;
                  manifest = ./tests/fixture/${name}.json;
                  pname = name;
                };
              in
              pkgs.runCommand "binary-test-${name}" { } ''
                ${pkgs.lib.getExe binary} </dev/null >/dev/null
                touch $out
              '';
          }) (builtins.filter pinned releases)
        );

        devShells.default = pkgs.mkShell {
          name = "nix-release-bin";
          packages = with pkgs; [
            bash
            jq
            perl
            python3
            shellcheck
            actionlint
          ];
        };
      }
    );
}
