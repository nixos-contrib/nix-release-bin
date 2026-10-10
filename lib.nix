# Packages the binary a GitHub release published for the host system, from a
# manifest the nix-release-bin action wrote. A system the release has no
# binary for gets the fallback, typically the package built from source.
{
  pkgs,
  # Path of the manifest, or its contents as an attribute set.
  manifest,
  # Name of the package, and of the program it installs.
  pname,
  # Package to use where the release has no binary.
  fallback ? null,
  # Meta attributes, the fallback's by default.
  meta ? fallback.meta or { },
}:
let
  release = if builtins.isAttrs manifest then manifest else builtins.fromJSON (builtins.readFile manifest);
  system = pkgs.stdenv.hostPlatform.system;
  asset = release.assets.${system} or null;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
if asset == null then
  if fallback != null then
    fallback
  else
    throw "${pname} ${release.version} has no release binary for ${system}"
else
  pkgs.stdenv.mkDerivation {
    inherit pname;
    inherit (release) version;
    # A binary Nix built refers to the libraries of the store it was built
    # in, and when those are in the fetcher's closure too, as they are when
    # the same nixpkgs installs it, a fixed-output derivation fetching it
    # fails. The builtin fetcher adds it to the store without building one,
    # at the cost of downloading it at evaluation.
    src = builtins.fetchurl {
      inherit (asset) url;
      sha256 = asset.hash;
    };
    dontUnpack = true;
    # A dynamically linked Linux binary Nix built loads the glibc of the store
    # it was built in, which the host's store does not hold, so it is pointed
    # at this one's instead. Static binaries are left alone.
    nativeBuildInputs = pkgs.lib.optionals isLinux [ pkgs.autoPatchelfHook ];
    buildInputs = pkgs.lib.optionals isLinux [ pkgs.stdenv.cc.cc.lib ];
    dontStrip = true;
    # Patching would invalidate the ad-hoc signature Go and Rust give darwin
    # binaries, so those are installed as published.
    dontFixup = !isLinux;
    installPhase = ''
      install -Dm0755 "$src" "$out/bin/${pname}"
    '';
    meta = meta // {
      mainProgram = pname;
      platforms = builtins.attrNames release.assets;
      sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
    };
  }
