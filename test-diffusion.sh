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

# ── GUI builds: run the same experiment with the Qt-OpenGL visualization ─────
# Needs a display: on Linux it runs under Xvfb (xvfb-run, with the system
# Mesa as OpenGL driver, as on a user's machine); on macOS it uses the
# logged-in GUI session.
case "$(basename "$PKG")" in
  *-gui_*) ;;
  *) exit 0 ;;
esac

if [[ "$(uname -s)" == "Linux" && -z "${DISPLAY:-}" ]]; then
  command -v xvfb-run >/dev/null \
    || { echo "ERROR: no DISPLAY and no xvfb-run to test the GUI build"; exit 1; }
  RUN_DISPLAY=(xvfb-run -a -s "-screen 0 1280x1024x24")
else
  RUN_DISPLAY=()
fi

# beta59: autoplay + headless_grabbing fast-forwards the experiment, saves
#   every 10th frame and quits when it ends, so the test checks that frames
#   were rendered and that they change over time (robots move): a missing
#   OpenGL context would crash, a broken one would give blank frames.
# beta48 has no headless_grabbing: the window never closes by itself, so the
#   test only checks that it is still running after a while without errors.
# The experiment's own <qt-opengl> node is kept (beta59's has a top-down
# camera that shows the robots); only the attributes/children are added.
GUI_EXPERIMENT="$EXAMPLES/experiments/diffusion_1_gui.argos"
case "$(basename "$PKG")" in
  argos3-3.0.0.0.beta59-*)
    GUI_MODE=frames
    # <qt-opengl> → <qt-opengl autoplay="true"><frame_grabbing .../>
    QT_SUBST='s|<qt-opengl>|<qt-opengl autoplay="true">\n      <frame_grabbing directory="frames" headless_grabbing="true" headless_frame_size="640x480" headless_frame_rate="10" />|'
    ;;
  *)
    GUI_MODE=alive
    # <qt-opengl ...> → <qt-opengl autoplay="true" ...>
    QT_SUBST='s|<qt-opengl\b|<qt-opengl autoplay="true"|'
    ;;
esac
perl -0pe "$QT_SUBST; s|length=\"0\"|length=\"10\"|" \
  "$EXAMPLES/experiments/diffusion_1.argos" > "$GUI_EXPERIMENT"
grep -q 'autoplay="true"' "$GUI_EXPERIMENT" && grep -q 'length="10"' "$GUI_EXPERIMENT" \
  || { echo "ERROR: could not adapt diffusion_1.argos for the GUI test"; exit 1; }
if [[ "$GUI_MODE" == frames ]] && ! grep -q 'headless_grabbing="true"' "$GUI_EXPERIMENT"; then
  echo "ERROR: could not add frame grabbing to diffusion_1.argos"; exit 1
fi

# Messages that mean the OpenGL context could not be created, or that icons
# and textures could not be loaded (install prefix broken by relocation).
GL_ERRORS='Failed to create|EGL not available|Could not (load|initialize|create)|cannot open display|Aborted|Segmentation fault|Broken filename|null image'

# run_gui <name> [VAR=value...]: runs the GUI experiment with the given extra
# environment, log in $EXAMPLES/gui-<name>.log, frames in $EXAMPLES/frames-<name>.
run_gui() {
  local name="$1"; shift
  local log="$EXAMPLES/gui-$name.log"
  local frames="$EXAMPLES/frames-$name"
  rm -rf "$EXAMPLES/frames" && mkdir -p "$EXAMPLES/frames"
  echo "── GUI test: $name ($GUI_MODE)"
  # shellcheck disable=SC2016  # expanded by the inner shell
  env "$@" ${RUN_DISPLAY[@]+"${RUN_DISPLAY[@]}"} pixi run --manifest-path "$WORK/pixi.toml" bash -c '
    cd "$1"
    argos3 -c experiments/diffusion_1_gui.argos &
    pid=$!
    if [[ "$2" == alive ]]; then
      sleep 20
      kill -0 "$pid" 2>/dev/null || { wait "$pid"; echo "argos3 exited early (status $?)"; exit 1; }
      kill "$pid"; wait "$pid" 2>/dev/null || true
    else
      # Watchdog: 10 s of simulation take a few seconds; give up after 120.
      ( sleep 120; kill "$pid" 2>/dev/null ) & watchdog=$!
      wait "$pid"; status=$?
      kill "$watchdog" 2>/dev/null || true
      exit "$status"
    fi
  ' _ "$EXAMPLES" "$GUI_MODE" > "$log" 2>&1 && status=0 || status=$?
  rm -rf "$frames" && mv "$EXAMPLES/frames" "$frames"
  # Keep log and frames for inspection (CI uploads them as an artifact).
  if [[ -n "${GUI_ARTIFACTS_DIR:-}" ]]; then
    mkdir -p "$GUI_ARTIFACTS_DIR"
    cp -R "$log" "$frames" "$GUI_ARTIFACTS_DIR/"
  fi
  cat "$log"
  [[ "$status" -eq 0 ]] || { echo "ERROR: GUI test '$name' failed (status $status)"; exit 1; }
  if grep -Eiq "$GL_ERRORS" "$log"; then
    echo "ERROR: GUI test '$name' printed OpenGL/display errors"; exit 1
  fi
  if [[ "$GUI_MODE" == frames ]]; then
    local pngs=("$frames"/*.png)
    [[ -f "${pngs[0]}" ]] || { echo "ERROR: GUI test '$name' saved no frames"; exit 1; }
    if cmp -s "${pngs[0]}" "${pngs[${#pngs[@]}-1]}"; then
      echo "ERROR: GUI test '$name': first and last frame are identical (nothing rendered?)"; exit 1
    fi
    echo "GUI test '$name': ${#pngs[@]} frames rendered in $frames"
  fi
}

run_gui default

# WSL: WSLg sets WAYLAND_DISPLAY and Qt 6 would pick Wayland, which fails
# there without EGL. The packaged patch (recipe/0001-wsl-qt-glx-defaults.patch)
# makes argos3 use xcb (and the Mesa GLX vendor) when WSL_DISTRO_NAME is set.
# Simulate that environment and check that the Wayland plugin is not even tried.
if [[ "$(uname -s)" == "Linux" && "$GUI_MODE" == frames ]]; then
  run_gui wsl WSL_DISTRO_NAME=CI WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland \
              QT_DEBUG_PLUGINS=1
  grep -q 'qxcb' "$EXAMPLES/gui-wsl.log" \
    || { echo "ERROR: WSL test: Qt did not load the xcb platform plugin"; exit 1; }
  if grep -qi 'qwayland\|wl_display' "$EXAMPLES/gui-wsl.log"; then
    echo "ERROR: WSL test: Qt tried the Wayland platform plugin"; exit 1
  fi
fi

echo "GUI tests passed with $(basename "$PKG")"
