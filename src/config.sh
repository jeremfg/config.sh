# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to manipulate dotenv configuration files
# It also supports files that have been encrypted using SOPS
# Files can contain the following special values, which will be replaced on read:
#   - @GIT_ROOT@: The root of the git repository where CWD is located

if [[ -z ${GUARD_CONFIG_SH} ]]; then
  GUARD_CONFIG_SH=1
else
  return
fi

# Load all configurations from specified file
#
# Parameters:
#   $1[in]: Configuration file
# Returns:
#   0: Success
#   1: Configuration file not found
config_load() {
  local _config_file="$1"
  if [[ -f "${_config_file}" ]]; then
    local _content
    # The file might be encrypted
    if command -v sops &>/dev/null &&
      sops --input-type dotenv filestatus "${_config_file}" &>/dev/null; then
      _content=$(sops --input-type dotenv --output-type dotenv -d "${_config_file}")
      logInfo "Read from encrypted ${_config_file}"
    else
      _content=$(cat "${_config_file}")
      logInfo "Read from ${_config_file}"
    fi
    # Parse special value @GIT_ROOT@
    if grep -q "@GIT_ROOT@" <<<"${CF_CWD}"; then
      local git_root
      if ! cf_git_find_root git_root "${CF_ROOT}"; then
        logError "Failed to find the root of the repository, required by ${_config_file}"
        return 1
      fi
      _content="${_content//"@GIT_ROOT@"/${git_root}}"
    fi
    logTrace <<EOF
Loading the following:

${_content}
EOF
    # shellcheck disable=SC1090 # Yes, the source file is dynamic by design
    source <(echo "${_content}")
    return 0
  else
    logError "Configuration file not found: ${_config_file}"
    return 1
  fi
}

# Persist a configuration to a specified file
#
# Parameters:
#   $1[in]: Configuration file
#   $2[in]: Configuration key
#   $3[in]: Configuration value
# Returns:
#   0: Success
#   1: Failure
config_save() {
  local _config_file="$1"
  local _config="$2"
  local _value="$3"

  # Validate all parameters
  if [[ -z "${_config_file}" ]]; then
    logError "Configuration file not provided"
    return 1
  fi
  if [[ -z "${_config}" ]]; then
    logError "Configuration key not provided"
    return 1
  fi

  # Config cannot contain spaces
  if [[ "${_config}" == *" "* ]]; then
    logError "Configuration key cannot contain spaces"
    return 1
  fi

  # Check if the file is encrypted
  if [[ ! -f "${_config_file}" ]]; then
    logWarn "Configuration file does not exist: ${_config_file}. A new one will not be encrypted"
    _content=""
  elif ! command -v sops &>/dev/null; then
    logWarn "Cannot check if file is encrypted, sops is not installed"
    # Pray that the original file was not encrypted
    _content=$(cat "${_config_file}")
  elif sops --input-type dotenv filestatus "${_config_file}" &>/dev/null; then
    # File is encrypted, decrypt it to a variable
    _content=$(sops --input-type dotenv --output-type dotenv -d "${_config_file}")
  else
    # File is not encrypted, read it into a variable
    _content=$(cat "${_config_file}")
  fi

  # If no value is provided, delete the configuration
  if [[ -z "${_value}" ]]; then
    logInfo "Deleting configuration: ${_config}"
    if grep -q "^${_config}=" <<<"${_content}"; then
      _content=$(echo "${_content}" | sed "/^${_config}=.*/d")
    else
      logWarn "Configuration did not exist: ${_config}"
      return 0
    fi
  else
    # If value contains spaces, wrap it in quotes
    if [[ "${_value}" == *" "* ]]; then
      _value="\"${_value}\""
    fi

    # Add or update the config in _content
    if grep -q "^${_config}=" <<<"${_content}"; then
      logInfo "Updating configuration: ${_config}"
      # shellcheck disable=SC2001
      if ! _content=$(echo "${_content}" | sed "s|^${_config}=.*|${_config}=${_value}|"); then
        logError "Failed to update configuration: ${_config}"
        return 1
      fi
    else
      logInfo "Adding configuration: ${_config}"
      if ! _content=$(echo -e "${_content}\n${_config}=${_value}"); then
        logError "Failed to add configuration: ${_config}"
        return 1
      fi
    fi
  fi

  # Save configuration to config file
  if [[ -f "${_config_file}" ]]; then
    if command -v sops &>/dev/null &&
      sops --input-type dotenv filestatus "${_config_file}" &>/dev/null; then
      if ! echo "${_content}" | sops --input-type dotenv --output-type dotenv -e /dev/stdin >"${_config_file}"; then
        logError "Failed to write encrypted configuration"
        return 1
      fi
      logInfo "Settings saved encrypted into ${_config_file}"
    else
      if ! echo "${_content}" >"${_config_file}"; then
        logError "Failed to write configuration"
        return 1
      fi
      logInfo "Settings saved into ${_config_file}"
    fi
  else
    if ! mkdir -p "$(dirname "${_config_file}")"; then
      logError "Failed to create directory: $(dirname "${_config_file}")"
      return 1
    fi
    # Do not encrypt by default
    if ! echo "${_content}" >"${_config_file}"; then
      logError "Failed to write configuration"
      return 1
    fi
    logInfo "Settings saved into newly created ${_config_file}"
  fi

  return 0
}

# Utility functions
# Search for the parent/root of the top repository,
# walking up submodules if present
#
# Parameters:
#   $1[out]: Top root found
#   $2[in]:  Start directory to search from
# Returns:
#   0: Top root found
#   1: Error, not even a valid location or git not installed
#   2: Not a git directory. $1=$2
cf_git_find_root() {
  local _root="${1}"
  local _start_dir="${2}"
  local _cur_dir

  if ! command -v git &>/dev/null; then
    logError "Git not installed"
    return 1
  fi

  # Cleanup start directory
  _start_dir=$(realpath "${_start_dir}")
  if [[ -z "${_start_dir}" ]]; then
    logError "Initial directory invalid"
    return 1
  fi

  # First, search up the hierarchy until we find a valid directory
  _cur_dir="${_start_dir}"
  while [[ ! -d "${_cur_dir}" ]]; do
    if [[ -z "${_cur_dir}" ]] || [[ "/" == "${_cur_dir}" ]]; then
      # We've reached the top without finding a directory. Assuming error
      logError "Stopped search after reaching root"
      return 1
    fi
    # Go one level up
    _cur_dir="$(realpath "${_start_dir}/..")"
  done

  # Ok, from this point we have a valid directory. Now we need to check for git
  if cd "${_cur_dir}" && git rev-parse --is-inside-work-tree &>/dev/null; then
    local _next_dir="${_cur_dir}"
    while true; do
      _next_dir="$(cd "${_cur_dir}" && git rev-parse --show-toplevel)/.."
      _next_dir="$(realpath "${_next_dir}")"
      if cd "${_next_dir}" && git rev-parse --is-inside-work-tree &>/dev/null; then
        _cur_dir="${_next_dir}"
      else
        _cur_dir="$(cd "${_cur_dir}" && git rev-parse --show-toplevel)"
        eval "${_root}='${_cur_dir}'"
        return 0
      fi
    done
  else
    # Not a git repository
    eval "${_root}='${_start_dir}'"
    return 2
  fi
}

###########################
###### Startup logic ######
###########################
CF_CWD=$(pwd)

# Get directory of this script
# https://stackoverflow.com/a/246128
CF_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${CF_SOURCE}" ]]; do # resolve $CF_SOURCE until the file is no longer a symlink
  CF_ROOT=$(cd -P "$(dirname "${CF_SOURCE}")" >/dev/null 2>&1 && pwd)
  CF_SOURCE=$(readlink "${CF_SOURCE}")
  [[ ${CF_SOURCE} != /* ]] && CF_SOURCE=${CF_ROOT}/${CF_SOURCE} # if $CF_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CF_ROOT=$(cd -P "$(dirname "${CF_SOURCE}")" >/dev/null 2>&1 && pwd)
CF_ROOT=$(realpath "${CF_ROOT}/..")

# Import dependencies
# shellcheck disable=SC1090 # shellcheck cannot follow dynamic source
if ! source ~/.local/lib/slf4.sh; then
  echo "ERROR: Failed to load logging library. Was it installed?"
  exit 1
fi

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  echo "ERROR: This script cannot be executed"
  exit 1
fi
