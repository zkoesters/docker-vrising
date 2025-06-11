#!/bin/bash

# Checks if a given path is a directory
# Returns 0 if the path is a directory
# Returns 1 if the path is not a directory or does not exists and produces an output message
dirExists() {
  local path="$1"
  local return_val=0
  if ! [ -d "${path}" ]; then
    echo "${path} does not exist."
    return_val=1
  fi
  return "$return_val"
}

# Checks if a given path is a regular file
# Returns 0 if the path is a regular file
# Returns 1 if the path is not a regular file or does not exists and produces an output message
fileExists() {
  local path="$1"
  local return_val=0
  if ! [ -f "${path}" ]; then
    echo "${path} does not exist."
    return_val=1
  fi
  return "$return_val"
}

# Checks if a given path exists and is readable
# Returns 0 if the path exists and is readable
# Returns 1 if the path is not readable or does not exists and produces an output message
isReadable() {
  local path="$1"
  local return_val=0
  if ! [ -e "${path}" ]; then
    echo "${path} is not readable."
    return_val=1
  fi
  return "$return_val"
}

# Checks if a given path is writable
# Returns 0 if the path is writable
# Returns 1 if the path is not writable or does not exists and produces an output message
isWritable() {
  local path="$1"
  local return_val=0
  # Directories may be writable but not deletable causing -w to return false
  if [ -d "${path}" ]; then
    temp_file=$(mktemp -q -p "${path}")
    if [ -n "${temp_file}" ]; then
      rm -f "${temp_file}"
    else
      echo "${path} is not writable."
      return_val=1
    fi
  # If it is a file it must be writable
  elif ! [ -w "${path}" ]; then
    echo "${path} is not writable."
    return_val=1
  fi
  return "$return_val"
}

# Checks if a given path is executable
# Returns 0 if the path is executable
# Returns 1 if the path is not executable or does not exists and produces an output message
isExecutable() {
  local path="$1"
  local return_val=0
  if ! [ -x "${path}" ]; then
    echo "${path} is not executable."
    return_val=1
  fi
  return "$return_val"
}

# RCON Call
RCON() {
  local args="$1"
  rcon-cli -c "${SCRIPTSDIR}/rcon.yaml" "$args"
}

broadcast_command() {
  local return_val=0
  # Replaces spaces with underscore
  local message="${1// /_}"
  if [[ $TEXT = *[![:ascii:]]* ]]; then
    LogWarn "Unable to broadcast since the message contains non-ascii characters: \"${message}\""
    return_val=1
  elif ! RCON "broadcast ${message}" >/dev/null; then
    return_val=1
  fi
  return "$return_val"
}

countdown_message() {
  local mtime="$1"
  local message_prefix="$2"
  local return_val=0

  if [[ "${mtime}" =~ ^[0-9]+$ ]]; then
    for ((i = "${mtime}"; i > 0; i--)); do
      case "$i" in
      1)
        broadcast_command "${message_prefix} in ${i} minute"
        sleep 30s
        broadcast_command "${message_prefix} in 30 seconds"
        sleep 20s
        broadcast_command "${message_prefix} in 10 seconds"
        sleep 10s
        ;;
      2) ;&
      3) ;&
      10) ;&
      15) ;&
      "$mtime")
        broadcast_command "${message_prefix} in ${i} minutes"
        ;&
      *)
        sleep 1m
        ;;
      esac
    done
  elif [ -z "${mtime}" ]; then
    return_val=1
  else
    return_val=2
  fi
  return "$return_val"
}

#
# Log Definitions
#
export LINE='\n'
export RESET='\033[0m'        # Text Reset
export WhiteText='\033[0;37m' # White

# Bold
export RedBoldText='\033[1;31m'    # Red
export GreenBoldText='\033[1;32m'  # Green
export YellowBoldText='\033[1;33m' # Yellow
export CyanBoldText='\033[1;36m'   # Cyan

LogInfo() {
  Log "$1" "$WhiteText"
}
LogWarn() {
  Log "$1" "$YellowBoldText"
}
LogError() {
  Log "$1" "$RedBoldText"
}
LogSuccess() {
  Log "$1" "$GreenBoldText"
}
LogAction() {
  Log "$1" "$CyanBoldText" "****" "****"
}
Log() {
  local message="$1"
  local color="$2"
  local prefix="$3"
  local suffix="$4"
  printf "$color%s$RESET$LINE" "$prefix$message$suffix"
}

# Send Discord Message
# Level is optional variable defaulting to info
DiscordMessage() {
  local title="$1"
  local message="$2"
  local level="$3"
  local enabled="$4"
  local webhook_url="$5"
  if [ -z "$level" ]; then
    level="info"
  fi
  if [ -n "${DISCORD_WEBHOOK_URL}" ]; then
    "${SCRIPTSDIR}"/discord.sh "$title" "$message" "$level" "$enabled" "$webhook_url" &
  fi
}

#
# Some functions to add color to outputs
# using IFS=''preserves whitespace
#
WineStdout() {
  while IFS= read -r line; do
    echo $'\e[1;30m'"$line"$'\e[0m'
  done
}

WindeStderr() {
  while IFS= read -r line; do
    >&2 echo $'\e[1;31m'"$line"$'\e[0m'
  done
}
# Function to remove ANSI escape codes and log STDOUT/STDERR
LogCleanOutput() {
  tee -a >(sed -u 's/\x1B\[[0-9;]*[JKmsu]//g' >"$LOGSDIR/latest.log")
}

# Try to parse RCON access info
# Returns 0 if the parse succeeded
# Returns 1 if the parse failed or rcon is disabled
ParseRCONAccess() {
  local host_settings_file="${STEAMAPPDATA}/Settings/ServerHostSettings.json"
  if ! [ -f "${host_settings_file}" ]; then
    local file_rcon_enabled
    file_rcon_enabled=$(jq -r .Rcon.Enabled <"${host_settings_file}")

    local file_rcon_port
    file_rcon_port=$(jq -r .Rcon.Port <"${host_settings_file}")

    local file_rcon_password
    file_rcon_password=$(jq -r .Rcon.Password <"${host_settings_file}")
  fi

  local rcon_enabled
  rcon_enabled=${VR_RCON_ENABLED:-"$file_rcon_enabled"}

  local rcon_port
  rcon_port=${VR_RCON_PORT:-"$file_rcon_port"}

  local rcon_password
  rcon_password=${VR_RCON_PASSWORD:-"$file_rcon_password"}

  if [ -z "${rcon_enabled}" ] || [ "${rcon_enabled,,}" = false ]; then
    return 1
  fi

  printf "default:\n  address: 127.0.0.1:%s\n  password: %s\n" "$rcon_port" "$rcon_password" \
    >"${SCRIPTSDIR}/rcon.yaml"
  return 0
}
