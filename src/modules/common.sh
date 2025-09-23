#!/bin/bash
# common.sh
# Depends on:
# Usage: source common.sh
[[ -n "${COMMON_SH_INCLUDED}" ]] && return
COMMON_SH_INCLUDED=1

# ----------------------------------------------------------------------
# ANSI color escape characters
# ----------------------------------------------------------------------
WHITE=$(printf '\033[97m')
GREEN=$(printf '\033[92m')
YELLOW=$(printf '\033[93m')
RED=$(printf '\033[91m')
RESET=$(printf '\033[0m')

# ----------------------------------------------------------------------
# Signal handling
# ----------------------------------------------------------------------
trap 'abort' INT
trap 'abort' TERM

# ----------------------------------------------------------------------
# Usage:   log <level> "<message>"
# Purpose: Simple leveled logger that writes to stderr.
# Parameters:
#   $1 – single‑letter level (d = DEBUG, i = INFO, w = WARNING, e = ERROR)
#   $2 – message text to log (quote if it contains spaces)
# Globals used:
#   DEBUG – if set to a non‑zero value, DEBUG messages are emitted;
#           otherwise they are suppressed.
# Returns: 0 (returns early only for suppressed DEBUG messages)
# Side‑Effects: writes to stderr (unless level is 'd' and DEBUG is turned off)
# ----------------------------------------------------------------------
log() {
   local level="$1"
   local msg="$2"
   local header

   if [[ $level == d && ( -z $DEBUG || $DEBUG == 0 ) ]]; then
      return 0
   fi
   case $level in
      'd') header="${WHITE}DEBUG${RESET}" ;;
      'i') header="${GREEN}INFO${RESET}" ;;
      'w') header="${YELLOW}WARNING${RESET}" ;;
      'e') header="${RED}ERROR${RESET}" ;;
   esac

   echo "${header} ${FUNCNAME[1]}: ${msg}" >&2
}

# ----------------------------------------------------------------------
# Usage: abort
# Purpose: Clean up temporary files, print a message and exit with status 1.
# Parameters: none
# Variables used: $tmpfile (temporary file name)
# Returns: never returns – calls 'exit 1'.
# ----------------------------------------------------------------------
abort() {
   rm -f "$tmpfile"
   log w "Application aborted."
   exit 1
}

# ----------------------------------------------------------------------
# Usage: app_exit
# Purpose: Normal termination (when user clicks “Exit” in a dialog).
# Parameters: none
# Variables used: none
# Returns: exits with status 0.
# ----------------------------------------------------------------------
app_exit() {
   log i "Exiting."
   exit 0
}

# ----------------------------------------------------------------------
# Usage: handle_exit_code <code>
# Purpose: Centralised handling of dialog exit codes.
# Parameters:
#   $1 – numeric exit code returned by a dialog command.
# Globals used:
#   step – current wizard step (incremented/decremented here).
# Returns: may call 'abort' on unknown codes; otherwise updates $step.
# ----------------------------------------------------------------------
handle_exit_code() {
   # Actions of dialog buttons
   case $1 in
      0) (( step++ )) ;;
      1) app_exit ;;
      2) ;;
      3) (( step-- )) ;;
      *) 
         log e "Unknown exit code - ${1}"
         abort
      ;;
   esac
}
