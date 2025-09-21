#!/bin/bash
# common.sh
# Depends on:
# Usage: source common.sh
[[ -n "${COMMON_SH_INCLUDED}" ]] && return
COMMON_SH_INCLUDED=1

# ----------------------------------------------------------------------
# Signal handling
# ----------------------------------------------------------------------
trap 'abort' INT
trap 'abort' TERM

# ----------------------------------------------------------------------
# Usage: abort
# Purpose: Clean up temporary files, print a message and exit with status 1.
# Parameters: none
# Variables used: $tmpfile (temporary file name)
# Returns: never returns – calls 'exit 1'.
# ----------------------------------------------------------------------
abort() {
    rm -f "$tmpfile"
    echo "Application aborted." >&2
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
    echo "Exiting." >&2
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
            echo "Error: Unknown exit code - ${1}" >&2
            abort
        ;;
    esac
}
