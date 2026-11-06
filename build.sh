#!/usr/bin/env bash
set -euxo pipefail

# ── Variant ───────────────────────────────────────────────────────────────────
# ARGOS_GUI=ON builds the Qt-OpenGL visualization (recipe/betaXX.yaml);
# ARGOS_GUI=OFF builds a headless simulator (recipe/betaXX-headless.yaml).
# The recipe sets it in build.script.env.
ARGOS_GUI="${ARGOS_GUI:-OFF}"
echo "ARGOS_GUI=$ARGOS_GUI"

# ── Create LICENSE file ───────────────────────────────────────────────────────
cat > "$SRC_DIR/LICENSE" << 'EOF'
MIT License

Copyright (c) Carlo Pinciroli and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# ── Patch missing C++ standard library includes ──────────────────────────────
# ARGoS3 beta59 was written against older compilers that pulled these in
# transitively. GCC 11+ and Clang 13+ require them explicitly.

patch_include() {
    local file="$SRC_DIR/src/$1"
    local header="$2"

    # Only patch if the include is genuinely missing
    if ! grep -q "#include.*${header}" "$file"; then
        perl -i -0pe 'BEGIN { $h = shift } s|^(#include)|#include $h\n$1|m' -- "$header" "$file"
        echo "Patched ${header} into $1"
    fi
}

# <iterator> — std::back_inserter
patch_include "core/utility/math/convex_hull.cpp" "<iterator>"

# <algorithm> — std::sort, std::find, std::remove_if, std::min_element
patch_include "core/simulator/entity/embodied_entity.cpp" "<algorithm>"
patch_include "plugins/simulator/physics_engines/dynamics3d/bullet/BulletCollision/CollisionDispatch/btUnionFind.cpp" "<algorithm>"
patch_include "plugins/simulator/physics_engines/dynamics3d/bullet/BulletCollision/CollisionDispatch/btSimulationIslandManager.cpp" "<algorithm>"
patch_include "plugins/robots/generic/simulator/camera_sensor_algorithms/camera_sensor_tag_detector_algorithm.h" "<algorithm>"

# <memory> — std::shared_ptr, std::make_shared, std::unique_ptr
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_model.h" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_gravity_plugin.cpp" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_single_body_object_model.cpp" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_multi_body_object_model.cpp" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_shape_manager.cpp" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_box_model.cpp" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_cylinder_model.cpp" "<memory>"
patch_include "plugins/simulator/physics_engines/dynamics3d/dynamics3d_model.cpp" "<memory>"
patch_include "plugins/robots/prototype/simulator/dynamics3d_prototype_model.cpp" "<memory>"
patch_include "plugins/robots/e-puck/simulator/dynamics3d_epuck_model.cpp" "<memory>"

# <functional> — std::less<T*>, std::bind, std::function
# std::less is defined in <functional>. On libc++ (macOS/Clang), <map> and
# <iterator> no longer pull it in transitively.
patch_include "core/utility/datatypes/set.h" "<functional>"
patch_include "core/simulator/physics_engine/physics_engine.h" "<functional>"
patch_include "core/control_interface/ci_sensor.h" "<functional>"
patch_include "core/control_interface/ci_actuator.h" "<functional>"
patch_include "plugins/robots/prototype/simulator/dynamics3d_prototype_model.cpp" "<functional>"

# <cstdint> — uint8_t, uint32_t, int32_t
patch_include "plugins/simulator/physics_engines/dynamics3d/bullet/LinearMath/btMatrix3x3.h" "<cstdint>"
patch_include "plugins/simulator/physics_engines/dynamics3d/bullet/LinearMath/btCpuFeatureUtility.h" "<cstdint>"

# tr1/unordered_map — entity.h has a platform ifdef that uses the pre-C++11
# tr1/ staging headers. The Linux branch unconditionally used tr1/ (written
# when GCC defaulted to C++03). Modern GCC and Clang no longer ship tr1/.
# Replace the entire ifdef block with a single C++11 include.
perl -i -0pe \
  's{#if defined\(__apple_build_version__\s*\).*?#endif}{#include <unordered_map>\nusing std::unordered_map;}s' \
  "$SRC_DIR/src/core/simulator/entity/entity.h"
echo "Patched tr1/unordered_map in entity.h"

# ── Keep the default plugin path valid after conda prefix relocation ─────────
# DEFAULT_PLUGIN_PATH is built from a literal containing $PREFIX. Clang bakes
# the literal's length into the std::string constructor, so after conda
# rewrites the prefix (padding with NULs) the string keeps the old length and
# contains embedded NULs: dlopen() then sees only the directory and fails with
# 'Can't load library "<prefix>/lib/argos3/"'. Reading the literal through a
# volatile pointer forces strlen() at runtime.
perl -i -pe \
  's|^(\s*)(const std::string CDynamicLoading::DEFAULT_PLUGIN_PATH = )(ARGOS_INSTALL_PREFIX "/lib/argos3/");|$1static const char* volatile pchDefaultPluginPath = $3;\n$1$2pchDefaultPluginPath;|' \
  "$SRC_DIR/src/core/utility/plugins/dynamic_loading.cpp"
grep -q 'pchDefaultPluginPath' "$SRC_DIR/src/core/utility/plugins/dynamic_loading.cpp" \
  || { echo "ERROR: could not patch DEFAULT_PLUGIN_PATH in dynamic_loading.cpp"; exit 1; }
echo "Patched DEFAULT_PLUGIN_PATH in dynamic_loading.cpp"

# CSimulator::GetInstallationDirectory() (inline, simulator.h) has the same
# problem: it returns ARGOS_INSTALL_PREFIX, so the Qt-OpenGL plugin builds the
# icon and texture dirs from a 255-char string with trailing NULs. Qt5 rejects
# such paths ('Broken filename passed to function', no icons, null ground
# texture); Qt6 happens to tolerate them. Same volatile-pointer fix.
perl -i -pe \
  's|^(\s*)return ARGOS_INSTALL_PREFIX;|$1const char* volatile pchInstallPrefix = ARGOS_INSTALL_PREFIX;\n$1return std::string(pchInstallPrefix);|' \
  "$SRC_DIR/src/core/simulator/simulator.h"
grep -q 'pchInstallPrefix' "$SRC_DIR/src/core/simulator/simulator.h" \
  || { echo "ERROR: could not patch GetInstallationDirectory in simulator.h"; exit 1; }
echo "Patched GetInstallationDirectory in simulator.h"

# ── Make ARGoSConfig.cmake find the environment it is installed in ───────────
# beta59 installs share/argos3/cmake/ARGoSConfig.cmake, which only looks under
# ${CMAKE_INSTALL_PREFIX} (/usr/local by default), so find_package(ARGoS) in a
# user project fails with 'Could not find ARGOS_INCLUDE_DIRS'. Derive the
# prefix from the file's own location (<prefix>/share/argos3/cmake) instead,
# and search it first so Lua and FreeImage also come from the same env.
# (beta48 does not ship this file.)
ARGOS_CONFIG="$SRC_DIR/src/cmake/ARGoSConfig.cmake"
if [[ -f "$ARGOS_CONFIG" ]]; then
  perl -i -pe 's|\$\{CMAKE_INSTALL_PREFIX\}|\${_ARGOS_PREFIX}|g' "$ARGOS_CONFIG"
  perl -i -0pe \
    's|^(#\n# Set the ARGOS_BUILD_FOR variable)|#\n# Locate the install prefix from this file (<prefix>/share/argos3/cmake)\n#\nget_filename_component(_ARGOS_PREFIX "\${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)\nset(CMAKE_PREFIX_PATH "\${_ARGOS_PREFIX}" \${CMAKE_PREFIX_PATH})\n\n$1|m' \
    "$ARGOS_CONFIG"
  grep -q 'get_filename_component(_ARGOS_PREFIX' "$ARGOS_CONFIG" \
    || { echo "ERROR: could not patch prefix lookup in ARGoSConfig.cmake"; exit 1; }
  echo "Patched prefix lookup in ARGoSConfig.cmake"

  # find_package(Lua) uses CMake's FindLua, which understands Lua 5.5 only
  # from CMake 4.3 on (lua.h now declares LUA_VERSION_MAJOR_N 5 instead of
  # LUA_VERSION_MAJOR "5"). Older CMake, the norm on Linux, rejects the header
  # and fails with 'Could NOT find Lua (missing: LUA_INCLUDE_DIR)'. lua is a
  # run dependency of this package, so take it from the env directly and parse
  # the version ourselves (both header styles).
  export ARGOS_LUA_LOOKUP='  find_path(LUA_INCLUDE_DIR lua.h PATHS "${_ARGOS_PREFIX}/include" NO_DEFAULT_PATH)
  find_library(LUA_LIBRARIES NAMES lua lua5.5 lua55 PATHS "${_ARGOS_PREFIX}/lib" NO_DEFAULT_PATH)
  if(NOT LUA_INCLUDE_DIR OR NOT LUA_LIBRARIES)
    message(FATAL_ERROR "Lua not found in ${_ARGOS_PREFIX}")
  endif()
  file(STRINGS "${LUA_INCLUDE_DIR}/lua.h" _ARGOS_LUA_VERSION_LINES
       REGEX "^#define[ \t]+LUA_VERSION_(MAJOR|MINOR)(_N)?[ \t]+\"?[0-9]+\"?")
  string(REGEX REPLACE ".*LUA_VERSION_MAJOR(_N)?[ \t]+\"?([0-9]+).*" "\\2" _ARGOS_LUA_MAJOR "${_ARGOS_LUA_VERSION_LINES}")
  string(REGEX REPLACE ".*LUA_VERSION_MINOR(_N)?[ \t]+\"?([0-9]+).*" "\\2" _ARGOS_LUA_MINOR "${_ARGOS_LUA_VERSION_LINES}")
  set(LUA_VERSION_STRING "${_ARGOS_LUA_MAJOR}.${_ARGOS_LUA_MINOR}")'
  perl -i -pe 's|^\s*find_package\(Lua REQUIRED\)\s*$|$ENV{ARGOS_LUA_LOOKUP}\n|' "$ARGOS_CONFIG"
  grep -q '_ARGOS_LUA_VERSION_LINES' "$ARGOS_CONFIG" \
    || { echo "ERROR: could not patch Lua lookup in ARGoSConfig.cmake"; exit 1; }
  echo "Patched Lua lookup in ARGoSConfig.cmake"
fi

# –– Resolve Lua library path (name differs across platforms) –––––––––––––––––
if [[ "$(uname)" == "Darwin" ]]; then
    LUA_LIB="$(ls "$PREFIX"/lib/liblua*.dylib 2>/dev/null | head -1)"
else
    LUA_LIB="$(ls "$PREFIX"/lib/liblua*.so* 2>/dev/null | head -1)"
fi
LUA_INCLUDE="$PREFIX/include"

echo "Lua lib:     $LUA_LIB"
echo "Lua include: $LUA_INCLUDE"

# ── Linux: keep string literals from sharing bytes with the install prefix ───
# GCC puts string literals in mergeable sections and GNU ld (with conda's
# -Wl,-O2) merges a literal into the tail of a longer one. In beta48 the "/"
# used by CDynamicLoading::LoadLibrary ended up as the last byte of
# "<prefix>/lib/argos3/". conda rewrites that prefix at install time to a
# shorter path padded with NULs, so the "/" became "" and relative library
# paths were tried as ".build/..." instead of "./build/...": every experiment
# with library="build/..." failed with "Can't load library". Without merging,
# no literal can overlap a prefix string. (macOS's ld64 does not tail-merge.)
if [[ "$(uname)" == "Linux" ]]; then
    NO_MERGE_FLAGS="-fno-merge-constants"
else
    NO_MERGE_FLAGS=""
fi
export CFLAGS="${CFLAGS:-} $NO_MERGE_FLAGS"
export CXXFLAGS="${CXXFLAGS:-} $NO_MERGE_FLAGS"

# ── Patch beta48 CMake for lua 5.4 ───────────────────────────────────────────
# beta48 has two problems that beta59 does not:
#
#  1. ARGoSBuildFlags.cmake does `set(CMAKE_CXX_FLAGS "-Wall")` — a plain set
#     with no ${CMAKE_CXX_FLAGS} prefix, which WIPES any -DCMAKE_CXX_FLAGS we
#     pass on the command line. We patch that line to append our -I flag.
#
#  2. find_package(Lua52) hardcodes lua 5.2 search paths. We replace it with
#     direct set() calls using the paths resolved above.
#
if [[ -f "$SRC_DIR/src/cmake/FindLua52.cmake" ]]; then

  # (1) Append the lua include dir to the hardcoded CMAKE_CXX_FLAGS line.
  #     The same plain set() also drops $CFLAGS/$CXXFLAGS, so add
  #     $NO_MERGE_FLAGS (see above) to both the C and the C++ line.
  perl -i -pe \
    "s|^set\\(CMAKE_CXX_FLAGS\\s+\"-Wall\"\\)|set(CMAKE_CXX_FLAGS \"-Wall -I$LUA_INCLUDE $NO_MERGE_FLAGS\")|; s|^set\\(CMAKE_C_FLAGS\\s+\"-Wall\"\\)|set(CMAKE_C_FLAGS \"-Wall $NO_MERGE_FLAGS\")|" \
    "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake"
  grep -q "^set(CMAKE_CXX_FLAGS \"-Wall -I" "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake" \
    && grep -q "^set(CMAKE_C_FLAGS \"-Wall $NO_MERGE_FLAGS\")" "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake" \
    || { echo "ERROR: could not patch C/CXX flags in ARGoSBuildFlags.cmake"; exit 1; }
  echo "--- ARGoSBuildFlags.cmake C/CXX flags lines:"
  grep -nE 'set\(CMAKE_CX?X?_FLAGS ' "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake"

  # (2) Replace find_package(Lua52) with direct paths
  perl -i -0pe \
    "s|find_package\\(Lua52\\)|set(LUA_INCLUDE_DIR \"$LUA_INCLUDE\" CACHE PATH \"\" FORCE)\nset(LUA_LIBRARIES \"$LUA_LIB\" CACHE FILEPATH \"\" FORCE)\nset(LUA_VERSION_STRING \"5.4\" CACHE STRING \"\" FORCE)\nset(LUA52_FOUND TRUE)|" \
    "$SRC_DIR/src/cmake/ARGoSBuildChecks.cmake"
  echo "--- ARGoSBuildChecks.cmake lua block:"
  grep -n -A5 'LUA_INCLUDE_DIR' "$SRC_DIR/src/cmake/ARGoSBuildChecks.cmake" | head -8

  # (3) LINUX-ONLY BUG: beta48 does
  #       set(CMAKE_SHARED_LINKER_FLAGS "-Wl,--no-as-needed")
  #     a plain set with no ${CMAKE_SHARED_LINKER_FLAGS}, which WIPES conda's
  #     -L$PREFIX/lib from LDFLAGS. That makes the linker unable to find
  #     freeimage, freeimageplus and lua, which all live in $PREFIX/lib.
  #     beta59 fixed this upstream by appending; we apply the same fix here.
  #     (macOS is unaffected: its branch already appends correctly.)
  perl -i -pe \
    's|^(\s*)set\(CMAKE_SHARED_LINKER_FLAGS "-Wl,--no-as-needed"\)|$1set(CMAKE_SHARED_LINKER_FLAGS "\${CMAKE_SHARED_LINKER_FLAGS} -Wl,--no-as-needed")|' \
    "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake"
  echo "--- ARGoSBuildFlags.cmake shared linker line:"
  grep -n 'CMAKE_SHARED_LINKER_FLAGS "' "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake"

  # (4) Belt and braces: add a global include_directories() right after the
  #     existing one at the top of CMakeLists.txt, before any add_subdirectory.
  perl -i -pe \
    "s|^include_directories\\(\\\$\\{CMAKE_SOURCE_DIR\\} \\\$\\{CMAKE_BINARY_DIR\\}\\)|include_directories(\\\${CMAKE_SOURCE_DIR} \\\${CMAKE_BINARY_DIR} $LUA_INCLUDE)|" \
    "$SRC_DIR/src/CMakeLists.txt"
  echo "--- CMakeLists.txt include_directories line:"
  grep -n 'include_directories' "$SRC_DIR/src/CMakeLists.txt" | head -3
fi

# ── beta48: look for Qt in the conda env, not only in Homebrew ───────────────
# On macOS, beta48's ARGoSCheckQTOpenGL.cmake runs `brew --cellar qt` and
# checks for Qt only when Homebrew has it. That skips the conda-forge Qt in
# $PREFIX, and on a runner with Homebrew Qt it would pick up the wrong Qt.
# Drop the Homebrew probe and always use find_package(Qt5), which searches
# CMAKE_PREFIX_PATH (= $PREFIX).
QT_CHECK_48="$SRC_DIR/src/cmake/ARGoSCheckQTOpenGL.cmake"
if [[ -f "$QT_CHECK_48" ]]; then
  # Replace the conditions in both if() and endif() so CMake does not warn
  # about mismatched arguments.
  perl -i -pe 's|\(APPLE AND \(NOT ARGOS_BREW_QT_CELLAR\)\)|(FALSE)|g; s|\(\(NOT APPLE\) OR ARGOS_BREW_QT_CELLAR\)|(TRUE)|g' "$QT_CHECK_48"
  grep -q '^if(FALSE)' "$QT_CHECK_48" && grep -q '^if(TRUE)' "$QT_CHECK_48" \
    || { echo "ERROR: could not patch Homebrew Qt lookup in ARGoSCheckQTOpenGL.cmake"; exit 1; }
  echo "Patched Homebrew Qt lookup in ARGoSCheckQTOpenGL.cmake"
fi

# ── GUI / headless CMake flags ────────────────────────────────────────────────
# Headless: make sure no Qt is picked up even if one is lying around on the
# build machine (ARGOS_FORCE_NO_QTOPENGL exists in beta59 only; disabling the
# Qt find_package calls covers beta48 too).
if [[ "$ARGOS_GUI" == "ON" ]]; then
  QT_FLAGS=(-DARGOS_FORCE_NO_QTOPENGL=OFF)
else
  QT_FLAGS=(
    -DARGOS_FORCE_NO_QTOPENGL=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_Qt5=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_Qt6=ON
  )
fi

# ── Configure ─────────────────────────────────────────────────────────────────
mkdir -p build_simulator
cd build_simulator

cmake "$SRC_DIR/src" \
    "${QT_FLAGS[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DARGOS_BUILD_FOR=simulator \
    -DARGOS_DOCUMENTATION=OFF \
    -DARGOS_INSTALL_LDSOCONF=OFF \
    -DFREEIMAGE_INCLUDE_PATH="$PREFIX/include" \
    -DFREEIMAGE_LIBRARY="$PREFIX/lib/libFreeImage${SHLIB_EXT}" \
    -DCMAKE_INSTALL_RPATH="$PREFIX/lib;$PREFIX/lib/argos3" \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON

make -j"${CPU_COUNT:-1}"
make install

# ── Make sure the variant is what it claims to be ────────────────────────────
# ARGoS silently skips the Qt-OpenGL plugin when Qt/OpenGL/GLUT are missing,
# so check the installed result instead of trusting the configure step.
if ls "$PREFIX"/lib/argos3/libargos3plugin_simulator_qtopengl.* >/dev/null 2>&1; then
  HAS_QTOPENGL=ON
else
  HAS_QTOPENGL=OFF
fi
if [[ "$HAS_QTOPENGL" != "$ARGOS_GUI" ]]; then
  echo "ERROR: ARGOS_GUI=$ARGOS_GUI but Qt-OpenGL plugin installed=$HAS_QTOPENGL"
  exit 1
fi

# ── Activation scripts ────────────────────────────────────────────────────────
# conda and pixi source etc/conda/activate.d/*.sh when the environment is
# activated; see recipe/activate.sh for the variables it sets.
mkdir -p "$PREFIX/etc/conda/activate.d" "$PREFIX/etc/conda/deactivate.d"
cp "$RECIPE_DIR/activate.sh"   "$PREFIX/etc/conda/activate.d/argos3_activate.sh"
cp "$RECIPE_DIR/deactivate.sh" "$PREFIX/etc/conda/deactivate.d/argos3_deactivate.sh"
