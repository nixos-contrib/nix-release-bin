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
      lib.mkReleaseBinary = import ./lib.nix;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        mkReleaseBinary = import ./lib.nix;
        lock = ./tests/fixture/lock.json;
        fallback = pkgs.writeShellScriptBin "fallback" "" // {
          meta.description = "fallback";
        };
        pinned = builtins.hasAttr system (builtins.fromJSON (builtins.readFile lock)).assets;

        failures = pkgs.lib.runTests {
          testFallsBackWithoutABinary = {
            expr =
              (mkReleaseBinary {
                inherit pkgs fallback;
                pname = "protoc-gen-go-aip";
                lock = {
                  version = "1.0.0";
                  assets = { };
                };
              }).name;
            expected = fallback.name;
          };
          testFailsWithoutABinaryOrFallback = {
            expr =
              (builtins.tryEval
                (mkReleaseBinary {
                  inherit pkgs;
                  pname = "protoc-gen-go-aip";
                  lock = {
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
                binary = mkReleaseBinary {
                  inherit pkgs fallback;
                  pname = "protoc-gen-go-aip";
                  lock = {
                    version = "1.0.0";
                    assets.${system} = {
                      url = "https://example.com/protoc-gen-go-aip-${system}";
                      hash = pkgs.lib.fakeHash;
                    };
                  };
                };
              in
              {
                inherit (binary) name;
                inherit (binary.meta) description mainProgram platforms;
                url = builtins.head binary.src.urls;
              };
            expected = {
              name = "protoc-gen-go-aip-1.0.0";
              description = "fallback";
              mainProgram = "protoc-gen-go-aip";
              platforms = [ system ];
              url = "https://example.com/protoc-gen-go-aip-${system}";
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
        # Fetches and runs a real release binary where the fixture pins one.
        // pkgs.lib.optionalAttrs pinned {
          binary =
            let
              binary = mkReleaseBinary {
                inherit pkgs lock;
                pname = "protoc-gen-go-aip";
              };
            in
            pkgs.runCommand "binary-test" { } ''
              ${pkgs.lib.getExe binary} </dev/null >/dev/null
              touch $out
            '';
        };

        devShells.default = pkgs.mkShell {
          name = "nix-release-bin";
          packages = with pkgs; [
            bash
            jq
            perl
            shellcheck
            actionlint
          ];
        };
      }
    );
}
