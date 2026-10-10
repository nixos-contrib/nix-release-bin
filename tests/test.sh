#!/usr/bin/env bash
# Runs nix-release-bin.sh against tests/fixture/release.json, served by a
# gh stub, and checks the manifest it wrote. Also installs a binary through
# lib.nix, which needs Nix.
#
# Usage: tests/test.sh [test_name...]

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script=$root/nix-release-bin.sh
fixture=$root/tests/fixture

# Serves $RELEASE for the release API path the script asks for, and fails
# for any other.
stub_gh() {
  mkdir -p "$scratch/$name/bin"
  cat >"$scratch/$name/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "api repos/example/example-app/releases/tags/v0.2.0" ] || exit 1
cat "$RELEASE"
EOF
  chmod +x "$scratch/$name/bin/gh"
}

# Changes into an empty directory to write the manifest in, with gh serving
# the given release.
setup() {
  release=${1:-$fixture/release.json}
  mkdir -p "$scratch/$name/work"
  cd "$scratch/$name/work"
  stub_gh
}

# Writes a copy of the fixture release, changed by a jq filter, and prints
# its path.
release_with() {
  mkdir -p "$scratch/$name"
  jq "$1" "$fixture/release.json" >"$scratch/$name/release.json"
  echo "$scratch/$name/release.json"
}

# Runs the script with the given VAR=value settings, recording its exit
# status in $status and its log in $log.
run() {
  log=$scratch/$name.log
  output=$scratch/$name.output
  : >"$output"
  set +e
  env PATH="$scratch/$name/bin:$PATH" RELEASE="$release" GITHUB_OUTPUT="$output" \
    TAG=v0.2.0 REPOSITORY=example/example-app "$@" "$script" >"$log" 2>&1
  status=$?
  set -e
}

output_of() {
  sed -n "s/^$1=//p" "$output"
}

expect() {
  local description=$1
  shift
  if ! "$@"; then
    echo "  expected: $description"
    echo "  --- log ---"
    sed 's/^/  /' "$log" 2>/dev/null || true
    exit 1
  fi
}

contains() {
  grep -qF -- "$2" "$1"
}

test_pins_the_release_binaries() {
  setup
  run
  expect "success" test "$status" -eq 0
  expect "the fixture manifest" diff "$fixture/manifest.json" .nix-release-bin-manifest.json
  expect "updated=true" test "$(output_of updated)" = true
  expect "version=0.2.0" test "$(output_of version)" = 0.2.0
}

test_pins_rust_target_triples() {
  setup "$(release_with '.assets |= map(.name |= sub("-aarch64-darwin$"; "-aarch64-apple-darwin") | .name |= sub("-x86_64-linux$"; "-x86_64-unknown-linux-musl"))')"
  run
  expect "success" test "$status" -eq 0
  expect "the systems" test "$(jq -r '.assets | keys | join(" ")' .nix-release-bin-manifest.json)" = "aarch64-darwin x86_64-linux"
  expect "the hashes" test "$(jq -c '[.assets[].hash]' .nix-release-bin-manifest.json)" = "$(jq -c '[.assets[].hash]' "$fixture/manifest.json")"
}

test_fails_on_gnu_and_musl_binaries_for_a_system() {
  setup "$(release_with '.assets += [.assets[1] | .name = "example-app-x86_64-unknown-linux-gnu"] | .assets[1].name = "example-app-x86_64-unknown-linux-musl"')"
  run
  expect "failure" test "$status" -ne 0
  expect "the reason" contains "$log" "more than one binary for x86_64-linux"
}

test_leaves_a_current_manifest_alone() {
  setup
  cp "$fixture/manifest.json" .nix-release-bin-manifest.json
  run
  expect "success" test "$status" -eq 0
  expect "updated=false" test "$(output_of updated)" = false
}

test_writes_the_given_manifest() {
  setup
  run MANIFEST_FILE=release.manifest.json
  expect "success" test "$status" -eq 0
  expect "the fixture manifest" diff "$fixture/manifest.json" release.manifest.json
}

test_fails_without_a_binary() {
  setup "$(release_with '.assets |= map(select(.name == "checksums.txt"))')"
  run
  expect "failure" test "$status" -ne 0
  expect "the reason" contains "$log" "no asset whose name ends in a system"
  expect "no manifest" test ! -e .nix-release-bin-manifest.json
}

test_fails_without_a_digest() {
  setup "$(release_with '.assets[0].digest = null')"
  run
  expect "failure" test "$status" -ne 0
  expect "the reason" contains "$log" "no SHA-256 digest for example-app-aarch64-darwin"
  expect "no manifest" test ! -e .nix-release-bin-manifest.json
}

test_fails_on_two_binaries_for_a_system() {
  setup "$(release_with '.assets += [.assets[0] | .name = "other-aarch64-darwin"]')"
  run
  expect "failure" test "$status" -ne 0
  expect "the reason" contains "$log" "more than one binary for aarch64-darwin"
}

# A binary built with the nixpkgs that installs it refers to libraries the
# fetcher depends on too, such as glibc, so a fixed-output derivation
# fetching it fails.
test_installs_a_binary_built_with_the_same_nixpkgs() {
  local serve=$scratch/$name/serve nixpkgs binary port manifest package
  mkdir -p "$serve"
  log=$scratch/$name.log
  nixpkgs="(builtins.getFlake \"path:$root\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}"
  binary=$(nix build --impure --no-link --print-out-paths --expr "$nixpkgs.hello" 2>"$log") || true
  expect "hello to build" test -n "$binary"
  cp "$binary/bin/hello" "$serve/hello"

  python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$serve" >"$scratch/$name.server" 2>&1 &
  server=$!
  trap 'kill "$server"' EXIT
  for _ in $(seq 50); do
    port=$(sed -n 's/.* port \([0-9]*\).*/\1/p' "$scratch/$name.server")
    [ -n "$port" ] && break
    sleep 0.1
  done
  expect "the server to start" test -n "$port"

  manifest=$(jq -nc --arg url "http://127.0.0.1:$port/hello" --arg hash "$(nix hash file "$serve/hello")" \
    --arg system "$(nix eval --impure --raw --expr builtins.currentSystem)" \
    '{version: "1.0.0", assets: {($system): {$url, $hash}}}')
  package=$(nix build --impure --no-link --print-out-paths --expr "
    import $root/lib.nix {
      pkgs = $nixpkgs;
      manifest = builtins.fromJSON ''$manifest'';
      pname = \"hello\";
    }" 2>>"$log") || true
  expect "the binary to install" test -n "$package"
  expect "the binary to run" test "$("$package/bin/hello")" = "Hello, world!"
}

# Each test runs in its own process, so set -e and cd stay contained.
if [ "${1:-}" = --run ]; then
  name=$2
  scratch=$3
  "$name"
  exit 0
fi

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  while read -r test; do
    tests+=("$test")
  done <<EOF
$(declare -F | awk '$3 ~ /^test_/ { print $3 }')
EOF
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

failed=0
for test in "${tests[@]}"; do
  if "$0" --run "$test" "$scratch"; then
    echo "ok   $test"
  else
    echo "FAIL $test"
    failed=$((failed + 1))
  fi
done

echo "${#tests[@]} tests, $failed failed"
[ "$failed" -eq 0 ]
