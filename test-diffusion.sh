#!/usr/bin/env bash
# Smoke-test a built argos3 package the way a user would use it: install it
# into a fresh pixi environment, build the footbot_diffusion controller from
# argos3-examples against it, and run the diffusion_1 experiment.
#
# Usage: test-diffusion.sh <path/to/argos3-*.conda>
#
# The experiment runs without visualization (the <visualization> block is
# stripped) and with a finite length, so it works for both the GUI and the
# headless builds and needs no display.
set -euo pipefail

PKG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[[ -f "$PKG" ]] || { echo "ERROR: package not found: $1"; exit 1; }

# ── Pick the argos3-examples revision matching the ARGoS version ─────────────
# Upstream examples follow the latest ARGoS: since beta58 they use
# find_package(ARGoS), which beta48 does not provide. 1864aa0 is the last
# revision written for beta48 (pkg-config + FindLua52 from the ARGoS install).
case "$(basename "$PKG")" in
  argos3-3.0.0.0.beta48-*)
    EXAMPLES_REF=1864aa01795d168c8e82e4e75960f2250c93bea0
    CMAKE_SPEC=">=3.8,<4"   # examples require cmake_minimum_required(2.8.12)
    ;;
  argos3-3.0.0.0.beta59-*)
    EXAMPLES_REF=261e22e273975d1e7fa363bf45e0ebfd9931fc22
    CMAKE_SPEC=">=3.8"
    ;;
  *)
    echo "ERROR: no argos3-examples revision known for $(basename "$PKG")"
    exit 1
    ;;
esac

# Resolve symlinks: on macOS mktemp returns /var/..., a link to /private/var/...,
# and pkg-config then fails to find argos3_simulator.pc when CMake runs from
# the symlinked path.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
echo "Package:  $PKG"
echo "Examples: $EXAMPLES_REF"
echo "Work dir: $WORK"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  PLATFORM=linux-64 ;;
  Linux-aarch64) PLATFORM=linux-aarch64 ;;
  Darwin-x86_64) PLATFORM=osx-64 ;;
  Darwin-arm64)  PLATFORM=osx-arm64 ;;
  *) echo "ERROR: unsupported platform $(uname -s)-$(uname -m)"; exit 1 ;;
esac

# ── Environment: the package under test + a toolchain to build the examples ──
cat > "$WORK/pixi.toml" << EOF
[workspace]
name = "argos3-test"
channels = ["conda-forge"]
platforms = ["$PLATFORM"]

[dependencies]
argos3 = { url = "file://$PKG" }
cxx-compiler = "*"
cmake = "$CMAKE_SPEC"
make = "*"
pkg-config = "*"
EOF
pixi install --manifest-path "$WORK/pixi.toml"

# ── argos3-examples ──────────────────────────────────────────────────────────
EXAMPLES="$WORK/argos3-examples"
git init -q "$EXAMPLES"
git -C "$EXAMPLES" fetch -q --depth 1 https://github.com/ilpincy/argos3-examples "$EXAMPLES_REF"
git -C "$EXAMPLES" checkout -q FETCH_HEAD

# Finite run, no visualization (0 = run forever; qt-opengl needs a display
# and waits for the user to press play).
EXPERIMENT="$EXAMPLES/experiments/diffusion_1_test.argos"
perl -0pe 's|<visualization>.*?</visualization>|<visualization />|s; s|length="0"|length="60"|' \
  "$EXAMPLES/experiments/diffusion_1.argos" > "$EXPERIMENT"
if ! grep -q 'length="60"' "$EXPERIMENT" || grep -q 'qt-opengl' "$EXPERIMENT"; then
  echo "ERROR: could not adapt diffusion_1.argos"
  exit 1
fi

# ── Build and run inside the activated environment ───────────────────────────
# The experiment loads build/controllers/footbot_diffusion/libfootbot_diffusion
# relative to the working directory, so build in <examples>/build and run
# from <examples>.
# shellcheck disable=SC2016  # expanded by the inner shell
pixi run --manifest-path "$WORK/pixi.toml" bash -euxo pipefail -c '
  cd "$1"
  argos3 --version
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build --target footbot_diffusion -j "$(getconf _NPROCESSORS_ONLN)"
  argos3 -n -c experiments/diffusion_1_test.argos
' _ "$EXAMPLES"

echo "diffusion_1 ran successfully with $(basename "$PKG")"
