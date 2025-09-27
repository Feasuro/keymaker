#!/bin/bash
# common.sh
# Depends on:
# Usage: source common.sh
[[ -n "${COMMON_SH_INCLUDED:-}" ]] && return
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
trap 'errexit_handler' EXIT

# ----------------------------------------------------------------------
# Usage:   log <level> "<message>"
# Purpose: Simple leveled logger that writes to stderr.
# Parameters:
#   $1 – single‑letter level (d = DEBUG, i = INFO, w = WARNING, e = ERROR)
#   $2 – message text to log (quote if it contains spaces)
# Globals used:
#   DEBUG – if set to a non‑zero value, DEBUG messages are emitted;
#           otherwise they are suppressed.
#   WHITE, GREEN, YELLOW, RED, RESET – ANSI terminal escape characters
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
   rm -f "${tmpfile:-}"
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
# Usage: error_handler (used in a trap for unexpected errors)
# Purpose: Error‑handling routine invoked automatically on script exit.
#          It distinguishes between normal termination paths and unexpected errors.
# Parameters: none (relies on Bash built‑ins)
# Variables used:
#   tmpfile   – temporary file name that should be cleaned up on exit
# Returns:  never returns directly – either logs the error and cleans up,
#           or does nothing for expected termination functions.
# Side‑Effects:
#   * Writes a formatted error message to stderr via `log e`.
#   * Removes the temporary file referenced by `$tmpfile` (if set).
# ----------------------------------------------------------------------
errexit_handler() {
   case ${FUNCNAME[1]} in
      abort|app_exit|main) ;;
      *) log e "
   ocurred in function: ${FUNCNAME[1]}
   command:             ${BASH_COMMAND}
   returned status:     $?"
         rm -f "${tmpfile:-}"
         ;;
   esac
}

# ----------------------------------------------------------------------
# Usage: handle_exit_code <code>
# Purpose: Centralised handling of dialog exit codes.
# Parameters:
#   $1 – numeric exit code returned by a dialog command.
# Variables used:
#   step – current wizard step (incremented/decremented here).
# Returns: may call 'abort' on unknown codes; otherwise updates $step.
# ----------------------------------------------------------------------
handle_exit_code() {
   local status=$1
   log d "\`${FUNCNAME[1]}\` exited with status ${status}"
   # Actions of dialog buttons
   case $status in
      0) (( step++ )) ;;
      1) app_exit ;;
      2) ;;
      3) (( step-- )) ;;
      255) app_exit ;;
      *) 
         log e "Unknown exit code - ${status}"
         abort
      ;;
   esac
}
