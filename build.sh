#!/usr/bin/env bash
# Builds ARGoS3 (simulator) for every recipe in recipe/.
# Source fixes live in recipe/patches/ and are applied by rattler-build
# (see `source.patches` in each recipe) before this script runs.
set -euxo pipefail

# ARGOS_GUI=ON builds the Qt-OpenGL visualization (recipe/betaXX.yaml),
# ARGOS_GUI=OFF a headless simulator (recipe/betaXX-headless.yaml).
ARGOS_GUI="${ARGOS_GUI:-OFF}"

# ── Linux: keep string literals from sharing bytes with the install prefix ───
# GCC puts string literals in mergeable sections and GNU ld (with conda's
# -Wl,-O2) merges a literal into the tail of a longer one. In beta48 the "/"
# used by CDynamicLoading::LoadLibrary ended up as the last byte of
# "<prefix>/lib/argos3/". conda rewrites that prefix at install time to a
# shorter path padded with NULs, so the "/" became "" and relative library
# paths were tried as ".build/..." instead of "./build/...". Without merging,
# no literal can overlap a prefix string. (macOS's ld64 does not tail-merge.)
# beta48 ignores $CFLAGS/$CXXFLAGS; its 0005 patch adds the flag itself.
if [[ "$(uname)" == "Linux" ]]; then
  export CFLAGS="${CFLAGS:-} -fno-merge-constants"
  export CXXFLAGS="${CXXFLAGS:-} -fno-merge-constants"
fi

# ── Headless: make sure no Qt is picked up, even one lying around ────────────
# ARGOS_FORCE_NO_QTOPENGL exists in beta59 only; disabling the Qt
# find_package calls covers beta48 too.
if [[ "$ARGOS_GUI" == "ON" ]]; then
  QT_FLAGS=(-DARGOS_FORCE_NO_QTOPENGL=OFF)
else
  QT_FLAGS=(
    -DARGOS_FORCE_NO_QTOPENGL=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_Qt5=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_Qt6=ON
  )
fi

# ── Configure, build, install ─────────────────────────────────────────────────
cmake -S "$SRC_DIR/src" -B build_simulator \
  "${QT_FLAGS[@]}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_RPATH="$PREFIX/lib;$PREFIX/lib/argos3" \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DARGOS_BUILD_FOR=simulator \
  -DARGOS_DOCUMENTATION=OFF \
  -DARGOS_INSTALL_LDSOCONF=OFF \
  -DFREEIMAGE_INCLUDE_PATH="$PREFIX/include" \
  -DFREEIMAGE_LIBRARY="$PREFIX/lib/libFreeImage${SHLIB_EXT}"

make -C build_simulator -j"${CPU_COUNT:-1}"
make -C build_simulator install

# ── Check the variant is what it claims to be ────────────────────────────────
# ARGoS silently skips the Qt-OpenGL plugin when Qt/OpenGL/GLUT are missing.
if compgen -G "$PREFIX/lib/argos3/libargos3plugin_simulator_qtopengl.*" >/dev/null; then
  HAS_QTOPENGL=ON
else
  HAS_QTOPENGL=OFF
fi
if [[ "$HAS_QTOPENGL" != "$ARGOS_GUI" ]]; then
  echo "ERROR: ARGOS_GUI=$ARGOS_GUI but Qt-OpenGL plugin installed=$HAS_QTOPENGL"
  exit 1
fi

# ── Activation scripts (sourced by conda/pixi on activation) ─────────────────
mkdir -p "$PREFIX/etc/conda/activate.d" "$PREFIX/etc/conda/deactivate.d"
cp "$RECIPE_DIR/activate.sh"   "$PREFIX/etc/conda/activate.d/argos3_activate.sh"
cp "$RECIPE_DIR/deactivate.sh" "$PREFIX/etc/conda/deactivate.d/argos3_deactivate.sh"
