# Changelog

## 1.0.0 (2026-10-10)


### ⚠ BREAKING CHANGES

* call the pinned binaries a manifest, in .nix-release-bin-manifest.json
* default the lock file to .nix-release-bin.json
* rename lib.mkReleaseBinary to lib.mkReleaseBin

### Features

* call the pinned binaries a manifest, in .nix-release-bin-manifest.json ([4117e56](https://github.com/nixos-contrib/nix-release-bin/commit/4117e56ae6c0eb6194ba65561c2761b625f2b874))
* default the lock file to .nix-release-bin.json ([92cc638](https://github.com/nixos-contrib/nix-release-bin/commit/92cc6380a2b6449c8311eff9698e2d58897c52f6))
* install GitHub release binaries instead of building from source ([cac54c6](https://github.com/nixos-contrib/nix-release-bin/commit/cac54c6e288299af7660e8aea311da3da5875ab2))
* pin binaries named by Rust target triple ([20b01d2](https://github.com/nixos-contrib/nix-release-bin/commit/20b01d26b42f3b4f5eb6c8a73608f63249783ee8))
* rename lib.mkReleaseBinary to lib.mkReleaseBin ([f045a8f](https://github.com/nixos-contrib/nix-release-bin/commit/f045a8fb8d8c8b6d05d49210879ff615187838b8))


### Bug Fixes

* install a Nix-built binary that refers to the installing nixpkgs' libraries ([#3](https://github.com/nixos-contrib/nix-release-bin/issues/3)) ([deee37f](https://github.com/nixos-contrib/nix-release-bin/commit/deee37f6c0dd3f619baad293903ddc8b4f85408b)), closes [#2](https://github.com/nixos-contrib/nix-release-bin/issues/2)
* run dynamically linked Linux binaries against the host store's glibc ([e69b46a](https://github.com/nixos-contrib/nix-release-bin/commit/e69b46a05fca2278aa49e19015da435b33d65f48))
