#!/usr/bin/env bash
set -euxo pipefail

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

# –– Resolve Lua library path (name differs across platforms) –––––––––––––––––
if [[ "$(uname)" == "Darwin" ]]; then
    LUA_LIB="$(ls "$PREFIX"/lib/liblua*.dylib 2>/dev/null | head -1)"
else
    LUA_LIB="$(ls "$PREFIX"/lib/liblua*.so* 2>/dev/null | head -1)"
fi
LUA_INCLUDE="$PREFIX/include"

echo "Lua lib:     $LUA_LIB"
echo "Lua include: $LUA_INCLUDE"

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

  # (1) Append the lua include dir to the hardcoded CMAKE_CXX_FLAGS line
  perl -i -pe \
    "s|^set\\(CMAKE_CXX_FLAGS\\s+\"-Wall\"\\)|set(CMAKE_CXX_FLAGS \"-Wall -I$LUA_INCLUDE\")|" \
    "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake"
  echo "--- ARGoSBuildFlags.cmake CXX flags line:"
  grep -n 'set(CMAKE_CXX_FLAGS' "$SRC_DIR/src/cmake/ARGoSBuildFlags.cmake"

  # (2) Replace find_package(Lua52) with direct paths
  perl -i -0pe \
    "s|find_package\\(Lua52\\)|set(LUA_INCLUDE_DIR \"$LUA_INCLUDE\" CACHE PATH \"\" FORCE)\nset(LUA_LIBRARIES \"$LUA_LIB\" CACHE FILEPATH \"\" FORCE)\nset(LUA_VERSION_STRING \"5.4\" CACHE STRING \"\" FORCE)\nset(LUA52_FOUND TRUE)|" \
    "$SRC_DIR/src/cmake/ARGoSBuildChecks.cmake"
  echo "--- ARGoSBuildChecks.cmake lua block:"
  grep -n -A5 'LUA_INCLUDE_DIR' "$SRC_DIR/src/cmake/ARGoSBuildChecks.cmake" | head -8

  # (3) Belt and braces: add a global include_directories() right after the
  #     existing one at the top of CMakeLists.txt, before any add_subdirectory.
  perl -i -pe \
    "s|^include_directories\\(\\\$\\{CMAKE_SOURCE_DIR\\} \\\$\\{CMAKE_BINARY_DIR\\}\\)|include_directories(\\\${CMAKE_SOURCE_DIR} \\\${CMAKE_BINARY_DIR} $LUA_INCLUDE)|" \
    "$SRC_DIR/src/CMakeLists.txt"
  echo "--- CMakeLists.txt include_directories line:"
  grep -n 'include_directories' "$SRC_DIR/src/CMakeLists.txt" | head -3
fi

# ── Configure ─────────────────────────────────────────────────────────────────
mkdir -p build_simulator
cd build_simulator

cmake "$SRC_DIR/src" \
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