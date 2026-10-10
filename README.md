# nix-release-bin

[![CI](https://github.com/nixos-contrib/nix-release-bin/actions/workflows/ci.yml/badge.svg)](https://github.com/nixos-contrib/nix-release-bin/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Install the binaries a GitHub release published, instead of building from
source, from a flake that keeps its source build as the fallback.

A flake that packages a tool with `buildGoModule` or `buildRustPackage`
compiles it on every machine that has no binary cache for it, even when the
project's releases already ship a binary per system. Nix only fetches what it
has a hash for, so installing those binaries means pinning a hash per system
on every release. This repository does both halves:

- **`lib.mkReleaseBin`** packages the pinned binary for the host system, or
  returns the fallback where the release has none.
- **The action** writes the manifest it reads, after a release is published.

## How it works

The action reads the release from the GitHub API. Every asset whose name ends
in a Nix system, such as `example-app-x86_64-linux` or
`example-app-aarch64-darwin`, or in the Rust target triple of one, such as
`example-app-x86_64-unknown-linux-musl` or `example-app-aarch64-apple-darwin`,
is written to the manifest under that system, with its download URL and the
SHA-256 digest GitHub recorded when it was uploaded, so nothing is downloaded.
Other assets, such as checksums or archives, are skipped.

```json
{
  "assets": {
    "aarch64-darwin": {
      "hash": "sha256-+AQjITG+6afzGz0cwTx2fsm10Q9a7gK9EVOpTtiRSrg=",
      "url": "https://github.com/example/example-app/releases/download/v0.2.0/example-app-aarch64-darwin"
    }
  },
  "version": "0.2.0"
}
```

The manifest is committed after the release, so it names the latest release,
not the commit it sits in. A commit built from source can be ahead of it; the
pinned binary never is.

The run fails when the release has no binary for any system, when two assets
are binaries for the same system, or when an asset has no digest: GitHub
records none for assets uploaded before June 2025.

A Linux binary that Nix built and linked dynamically loads glibc from the
store it was built in, which other machines do not have, so its interpreter
and libraries are pointed at the nixpkgs passed in, as nixpkgs does for its
`-bin` packages. Static binaries, and every macOS binary, are installed as
published: patching a macOS binary would invalidate its ad-hoc signature.

## Usage

### The flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-release-bin = {
      url = "github:nixos-contrib/nix-release-bin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    { nixpkgs, flake-utils, nix-release-bin, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        source = pkgs.buildGoModule { pname = "example-app"; /* ... */ };
      in
      {
        packages = {
          default = nix-release-bin.lib.mkReleaseBin {
            inherit pkgs;
            manifest = ./.nix-release-bin-manifest.json;
            pname = "example-app";
            fallback = source;
          };
          inherit source;
        };
      }
    );
}
```

| Argument | Default | Description |
|---|---|---|
| `pkgs` | | Nixpkgs for the host system. |
| `manifest` | | Path of the manifest, or its contents as an attribute set. |
| `pname` | | Name of the package, and of the program it installs. |
| `fallback` | `null` | Package to use where the release has no binary. Without one, evaluating the package there fails. |
| `meta` | `fallback.meta` | Meta attributes. `mainProgram`, `platforms` and `sourceProvenance` are set from the binary. |

Build the release binaries from `.#source`, not `.#default`, or the release
workflow packages the previous release's binaries again.

### The workflow

Run the action once the release has its binaries, and open a pull request with
the manifest:

```yaml
  pin:
    needs: [release, publish]
    runs-on: ubuntu-latest
    permissions:
      contents: read
    timeout-minutes: 10
    steps:
      - name: Generate App token
        id: app-token
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.APP_CLIENT_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Checkout
        uses: actions/checkout@v7
        with:
          token: ${{ steps.app-token.outputs.token }}

      - name: Pin release binaries
        id: pin
        uses: nixos-contrib/nix-release-bin@v1
        with:
          tag: ${{ needs.release.outputs.tag_name }}

      - name: Create Pull Request
        if: steps.pin.outputs.updated == 'true'
        uses: peter-evans/create-pull-request@v8
        with:
          token: ${{ steps.app-token.outputs.token }}
          branch: nix/release-binaries
          commit-message: "chore(nix): pin the ${{ steps.pin.outputs.version }} release binaries"
          title: "chore(nix): pin the ${{ steps.pin.outputs.version }} release binaries"
          labels: auto-merge
```

A pull request opened with `GITHUB_TOKEN` starts no workflow runs, so its
required checks would never report. Use a GitHub App token, as above, or a
personal access token.

## Inputs

| Name | Default | Description |
|---|---|---|
| `tag` | | Tag of the release. Its version is the tag without a leading `v`. |
| `repository` | `${{ github.repository }}` | `owner/name` of the repository that published the release. |
| `manifest-file` | `.nix-release-bin-manifest.json` | Path of the manifest to write, relative to `working-directory`. |
| `working-directory` | `.` | Directory the manifest path is relative to. |
| `token` | `${{ github.token }}` | Token to read the release with. |

The action uses `gh`, `jq` and `perl`, which GitHub-hosted runners already
have. It needs no Nix.

## Outputs

| Name | Description |
|---|---|
| `updated` | `true` when the manifest changed, otherwise `false`. |
| `version` | Version written in the manifest. |

## Development

The dev shell carries the tools CI uses. Enter it with `nix develop`, or open
the repository in its devcontainer, which installs Nix.

`tests/test.sh` runs the script against `tests/fixture/release.json`, served
by a `gh` stub. The flake checks test `lib.nix`, and fetch and run the
binaries of two real releases for the host system: one static, pinned in
`tests/fixture/protoc-gen-go-aip.json`, and one dynamically linked, pinned in
`tests/fixture/protoc-gen-rust-aip.json`:

```sh
nix develop --command tests/test.sh                                # every test
nix develop --command tests/test.sh test_pins_the_release_binaries # one test
nix flake check
nix develop --command shellcheck nix-release-bin.sh tests/test.sh
nix develop --command actionlint
```

Releases are cut by release-please from Conventional Commits. Each release
also moves the major version tag, such as `v1`, that callers pin.

## License

[MIT](LICENSE)
