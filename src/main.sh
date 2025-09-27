#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------
APPNAME="Keybuilder" # program name.
VERSION="0.2"          # program version
DEBUG=${DEBUG:-1}  # if not-null causes app to print verbose messages to `stderr`.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # installation directory.
SHARED_DIR="/usr/share/${APPNAME,,}" 
GLOBAL_CONFIG_FILE="/etc/${APPNAME,,}.conf"        # location of configuration file.
USER_CONFIG_FILE="${XDG_CONFIG_HOME:-"${HOME}/.config"}/${APPNAME,,}.conf" # as above (per user)

# Import modules
for module in "${BASE_DIR}/modules/"*.sh; do
   source "$module"
done

# Determine resources path (if running portable)
if [[ $(basename "$(dirname "$BASE_DIR")") == "${APPNAME,,}" ]]; then
   SHARED_DIR=$(dirname "$BASE_DIR")
elif [[ -d $SHARED_DIR ]]; then
   :
else
   log e "Couldn't find shared directory."
   abort
fi

# Import configuration
if [[ -f $GLOBAL_CONFIG_FILE ]]; then
   source "$GLOBAL_CONFIG_FILE"
elif [[ -f "${BASE_DIR}/config.sh" ]]; then
   source "${BASE_DIR}/config.sh"
else
   log e "Couldn't find configuration file."
   abort
fi

if [[ -f $USER_CONFIG_FILE ]]; then
   source "$USER_CONFIG_FILE"
fi

# ----------------------------------------------------------------------
# Usage: main "$@"
# Purpose: Entry point for the program. Declares variables that represent
#          the current state of the program.
# Parameters: all arguments passed to the original script.
# Variables declared: (look utils.sh / set_partition_vars)
#   step                – step of the wizard (start with 1)
#   message             – message for the user to display on dialog box
#   device              – selected block device (e.g. /dev/sdb)
#   sector_size         – bytes per sector (from `blockdev --getss`)
#   offset              – first usable sector (after 1 MiB)
#   usable_size         – sectors available for partitions (excluding GPT backup)
#   part_sizes[]        – size of each partition (in sectors)
#   part_names[]        – human‑readable GPT labels
#   min_sizes[]         – minimal partition sizes (in sectors)
#   part_nodes[]        – device node names for each partition (e.g. /dev/sdb1)
#   partitions[]        – indexed array (size 4) of flags (0/1) indicating which
#                         partitions are selected
#   removable_devices[] – associative array mapping a device path to a
#                         human‑readable label
# Returns: int
#   It exits the script with status of the program loop.
# Side‑Effects
#   * May re‑execute the script with `sudo` or `pkexec` via `require_root`.
#   * Declares numerous variables that represent the state of the wizard.
#   * Runs program loop.
# ----------------------------------------------------------------------
main() {
   require_root "$@"

   local backtitle step message device sector_size offset usable_size 
   local -a partitions part_sizes part_names min_sizes part_nodes
   local -A removable_devices

   run_loop
}

main "$@"
