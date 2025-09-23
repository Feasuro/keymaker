#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------
BACKTITLE="Keybuilder" # program name.
VERSION="0.1"          # program version
DEBUG=${DEBUG:-1}  # if not-null causes app to print verbose messages to `stderr`.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # installation directory.
GLOBAL_CONFIG_FILE="/etc/keybuilder.conf"        # location of configuration file.
USER_CONFIG_FILE="${XDG_CONFIG_HOME:-"${HOME}/.config"}/keybuilder.conf" # as above (per user)

# ----------------------------------------------------------------------
# Configuration & modules
# ----------------------------------------------------------------------
if [[ -f $GLOBAL_CONFIG_FILE ]]; then
   source "$GLOBAL_CONFIG_FILE"
elif [[ -f "${BASE_DIR}/config.sh" ]]; then
   source "${BASE_DIR}/config.sh"
else
   echo "ERROR: Couldn't find configuration file." >&2
   exit 1
fi

if [[ -f $USER_CONFIG_FILE ]]; then
   source "$USER_CONFIG_FILE"
fi

for module in "${BASE_DIR}/modules/"*.sh; do
   source "$module"
done

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

   local step message device sector_size offset usable_size 
   local -a partitions part_sizes part_names min_sizes part_nodes
   local -A removable_devices

   run_loop
}

main "$@"
