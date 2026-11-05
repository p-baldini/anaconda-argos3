# shellcheck shell=sh
# Sourced by conda when the environment is deactivated (installed as
# etc/conda/deactivate.d/argos3_deactivate.sh). Restores the values saved by
# activate.sh, or unsets the variables if they were not set before.

if [ -n "${_ARGOS3_BACKUP_CMAKE_INSTALL_PREFIX+x}" ]; then
    export CMAKE_INSTALL_PREFIX="$_ARGOS3_BACKUP_CMAKE_INSTALL_PREFIX"
    unset _ARGOS3_BACKUP_CMAKE_INSTALL_PREFIX
else
  unset CMAKE_INSTALL_PREFIX
fi
if [ -n "${_ARGOS3_BACKUP_CMAKE_PREFIX_PATH+x}" ]; then
    export CMAKE_PREFIX_PATH="$_ARGOS3_BACKUP_CMAKE_PREFIX_PATH"
    unset _ARGOS3_BACKUP_CMAKE_PREFIX_PATH
else
  unset CMAKE_PREFIX_PATH
fi
if [ -n "${_ARGOS3_BACKUP_ARGoS_DIR+x}" ]; then
    export ARGoS_DIR="$_ARGOS3_BACKUP_ARGoS_DIR"
    unset _ARGOS3_BACKUP_ARGoS_DIR
else
    unset ARGoS_DIR
fi
