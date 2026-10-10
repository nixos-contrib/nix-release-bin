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
in
if asset == null then
  if fallback != null then
    fallback
  else
    throw "${pname} ${release.version} has no release binary for ${system}"
else
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname;
    inherit (release) version;
    src = pkgs.fetchurl { inherit (asset) url hash; };
    dontUnpack = true;
    # Stripping or patching would invalidate the ad-hoc signature Go and Rust
    # give darwin binaries, so the binary is installed as published.
    dontFixup = true;
    installPhase = ''
      install -Dm0755 "$src" "$out/bin/${pname}"
    '';
    meta = meta // {
      mainProgram = pname;
      platforms = builtins.attrNames release.assets;
      sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
    };
  }
