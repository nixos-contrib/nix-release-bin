#!/usr/bin/env bash
# Pins the binaries a GitHub release published in the lock file
# lib.mkReleaseBin reads, so a flake can install them instead of building
# from source.
#
# Every asset whose name ends in a Nix system, as example-app-x86_64-linux
# does, is written with its download URL and the SHA-256 digest GitHub
# recorded on upload, so nothing is downloaded. Other assets, such as
# checksums or archives, are skipped.
#
# Kept to bash 3.2, the /bin/bash macOS runners ship. Needs gh, jq and perl,
# which GitHub-hosted runners carry.
#
# Environment:
#   TAG         Tag of the release. Its version is the tag without a leading "v".
#   REPOSITORY  owner/name of the repository that published the release.
#   LOCK_FILE   Path of the lock file to write.
#   GH_TOKEN    Token to read the release with.

set -euo pipefail

: "${TAG:?TAG must name the release}"
: "${REPOSITORY:?REPOSITORY must name the repository, as owner/name}"
LOCK_FILE=${LOCK_FILE:-nix/release.json}

# The systems Nix builds for that release binaries are published for.
SYSTEM='-(?<system>(aarch64|x86_64|i686|armv6l|armv7l|riscv64|powerpc64le)-(linux|darwin))$'

release=$(gh api "repos/$REPOSITORY/releases/tags/$TAG")

assets=$(
  printf '%s' "$release" | jq -r --arg system "$SYSTEM" '
    .assets[] | select(.name | test($system))
    | [(.name | capture($system).system), .name, .browser_download_url, (.digest // "")]
    | @tsv
  '
)
if [ -z "$assets" ]; then
  echo "::error::Release $TAG of $REPOSITORY has no asset whose name ends in a system, such as -x86_64-linux."
  exit 1
fi

lock=$(jq -n --arg version "${TAG#v}" '{version: $version, assets: {}}')
while IFS="$(printf '\t')" read -r system name url digest; do
  if printf '%s' "$lock" | jq -e --arg system "$system" '.assets | has($system)' >/dev/null; then
    echo "::error::Release $TAG has more than one binary for $system, so it is unclear which to pin."
    exit 1
  fi
  case $digest in
    sha256:*) ;;
    *)
      echo "::error::GitHub recorded no SHA-256 digest for $name. Assets uploaded before June 2025 have none: upload it again."
      exit 1
      ;;
  esac

  hash="sha256-$(perl -e 'print pack("H*", $ARGV[0])' "${digest#sha256:}" | base64)"
  lock=$(
    printf '%s' "$lock" |
      jq --arg system "$system" --arg url "$url" --arg hash "$hash" '.assets[$system] = {url: $url, hash: $hash}'
  )
  echo "Pinned $name for $system."
done <<EOF
$assets
EOF

mkdir -p "$(dirname "$LOCK_FILE")"
previous=$(cat "$LOCK_FILE" 2>/dev/null || true)
printf '%s' "$lock" | jq --sort-keys . >"$LOCK_FILE"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "updated=$([ "$previous" != "$(cat "$LOCK_FILE")" ] && echo true || echo false)" >>"$GITHUB_OUTPUT"
  echo "version=${TAG#v}" >>"$GITHUB_OUTPUT"
fi
