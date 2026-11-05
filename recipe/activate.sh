# shellcheck shell=sh
# Sourced by conda and pixi when the environment is activated (installed as
# etc/conda/activate.d/argos3_activate.sh). Points CMake at the env so user
# projects resolve ARGoS there instead of /usr/local:
#     CMAKE_INSTALL_PREFIX  the env (read from the environment by CMake >= 3.29)
#     CMAKE_PREFIX_PATH     the env, prepended to any existing entries
#     ARGoS_DIR             the folder holding ARGoSConfig.cmake (beta59 only)
# Previous values are saved here and restored by deactivate.sh.

if [ -n "${CMAKE_INSTALL_PREFIX+x}" ]; then
    export _ARGOS3_BACKUP_CMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX"
fi
if [ -n "${CMAKE_PREFIX_PATH+x}" ]; then
    export _ARGOS3_BACKUP_CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"
fi
if [ -n "${ARGoS_DIR+x}" ]; then
    export _ARGOS3_BACKUP_ARGoS_DIR="$ARGoS_DIR"
fi
export CMAKE_INSTALL_PREFIX="$CONDA_PREFIX"
export CMAKE_PREFIX_PATH="$CONDA_PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export ARGoS_DIR="$CONDA_PREFIX/share/argos3/cmake"
