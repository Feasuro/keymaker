#!/bin/bash
# loop.sh
# Depends on: dialogs.sh utils.sh common.sh
# Usage: source loop.sh and deps, in any order.
[[ -n "${LOOP_SH_INCLUDED}" ]] && return
LOOP_SH_INCLUDED=1

# ----------------------------------------------------------------------
# Usage: require_root "$@"
# Purpose: Ensure the script runs with root privileges. If not already
#          root, re‑executes itself via `sudo` (preferred) or `pkexec`.
# Parameters: all arguments passed to the original script.
# Variables used: none
# Returns: does not return – either continues as root or aborts.
# ----------------------------------------------------------------------
require_root() {
    # If we are already uid 0 (root) there is nothing to do
    [[ $(id -u) -eq 0 ]] && return 0

    # Prefer sudo
    if command -v sudo >/dev/null 2>&1; then
        echo "INFO require_root: Requesting root privileges via sudo." >&2
        exec sudo -E "$0" "$@"
    # Fallback to pkexec
    elif command -v pkexec >/dev/null 2>&1; then
        echo "INFO require_root: Requesting root privileges via pkexec." >&2
        exec pkexec "$0" "$@"
    else
        echo "Error: neither sudo nor pkexec is available. Cannot obtain root." >&2
        abort
    fi
}

# ----------------------------------------------------------------------
# Usage: run_loop "$@"
# Purpose: Assemble the main loop for an interactive wizard that prepares
#          a removable USB device and installs a bootloader.
# Parameters: none
# Variables used/set:
#   step    – step of the wizard (start with 1)
#   message – set to empty string
# Returns: int
#   It exits the loop with status 0 after completing last step or propagates
#   any non‑zero exit status from called functions that invoke `abort`.
# Side‑Effects
#   * Interacts with the user through a series of `dialog` windows.
#   * Writes to standard error for progress messages.
#   * Modifies numerous variables that represent the current state
#     of the wizard.
# ----------------------------------------------------------------------
run_loop() {
    message=''
    step=1

    while true; do
        case $step in
            1)
                find_devices
                pick_device
                ;;
            2)
                pick_partitions
                set_partition_vars
                ;;
            3)
                set_partitions_size
                ;;
            4)
                confirm_format
                ;;
            5)
                echo "Finished." >&2
                break
                ;;
        esac
    done
}
