#!/bin/bash
# helper_dialogs.sh
# Depends on: common.sh
# Usage: source helper_dialogs.sh and deps, in any order.
[[ -n "${HELPER_DIALOGS_SH_INCLUDED:-}" ]] && return
HELPER_DIALOGS_SH_INCLUDED=1

# ----------------------------------------------------------------------
# Usage: manual_dev_entry
# Purpose: Prompt the user to type a device path manually (advanced mode).
# Parameters: none
# Variables used/set:
#   backtitle   – application name.
#   device      – variable receiving the selected device path.
# Returns:
#   0 – a valid device was entered,
#   2 – user cancelled or entered an invalid device.
# Side‑Effects:
#   * Displays input `dialog` where user can enter a device.
# ----------------------------------------------------------------------
manual_dev_entry() {
   local result devtype

   # Show dialog
   result=$(dialog --keep-tite --stdout \
      --backtitle "$backtitle" \
      --title "Enter device" \
      --inputbox "Enter device name (e.g. /dev/sdX)" 10 40
   ) || return 2

   # Check if a block device was given
   if [[ -b $result ]]; then
      devtype="$(lsblk -lnd -o TYPE "$result")"
      # Check if it is a disk, ask for confirmation if not
      if [[ $devtype = 'disk' ]]; then
         device="$result"
         return 0
      elif dialog --keep-tite \
            --backtitle "$backtitle" \
            --title "Warning" \
            --yesno "${result} appears to be ${devtype} not a disk.\nAre you sure you know what you are doing?" 10 40
         then
         device="$result"
         return 0
      fi
   else
      dialog --keep-tite \
         --backtitle "$backtitle" \
         --title "Warning" \
         --msgbox "${result} is not a valid block device!" 10 40
   fi
   return 2
}

# ----------------------------------------------------------------------
# Usage: request_manual_unmount
# Purpose: Prompt the user to unmount partitions manually.
# Parameters: none
# Variables used/set:
#   backtitle   – application name.
#   device      – variable receiving the selected device path.
# Returns: 0 – when user presses ok
# Side‑Effects: Displays `dialog` with a message.
# ----------------------------------------------------------------------
request_manual_unmount() {
   local msg

   msg="Device ${device} has some partitions mounted.
\ZbAutomatic unmount failed.\ZB
Partitions may be currently in use.

Unmount any mounted ${device}N partition
manually and press OK to continue."

   dialog --keep-tite --colors \
      --backtitle "$backtitle" \
      --title "Warning" \
      --yes-label "OK" \
      --no-label "Exit" \
      --yesno "${msg}" 10 50
}

# ----------------------------------------------------------------------
# Usage: check_uefi
# Purpose: Check if running in UEFI mode. If not prompt the user about
#          UEFI requirement.
# Parameters: none
# Variables used/set:
#   backtitle   – application name.
# Returns:
#   0 – UEFI detected
#   1 – non-UEFI system
# Side‑Effects:
#   * Displays `dialog` with a message.
# ----------------------------------------------------------------------
check_uefi() {
   local msg

   if [ ! -d /sys/firmware/efi ]; then
      log w "Running in non-UEFI mode!"

      msg="System is running in legacy BIOS mode.
\ZbProgram requires UEFI\ZB to continue bootloader installation.
Please reboot the system into UEFI mode to continue."

      dialog --keep-tite --colors \
         --backtitle "$backtitle" \
         --title "Error" \
         --msgbox "$msg" 10 50

      return 1
   fi

   return 0
}
