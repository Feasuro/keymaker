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

# ----------------------------------------------------------------------
# Usage: confirm_detected_partitions <status>
# Purpose: Summarise the result of `detect_target_partitions` and let the
#          user decide how to proceed.
# Parameters:       $1 – bitmask returned by `detect_target_partitions`.
# Variables used/set:
#   backtitle          – application name.
#   part_nodes[]       – populated by `detect_target_partitions`.
#   messages[]         – associative array of human‑readable warnings.
# Returns:
#   0 – user accepted the detected layout,
#   2 – user cancelled or manual selection failed.
# Side‑Effects:
#   * Invokes `detect_target_partitions`
#   * Shows a `dialog` with a colour‑coded summary.
#   * May invoke `manual_syspart_select` if user opts to select partition manually.
# ----------------------------------------------------------------------
confirm_detected_partitions() {
   local status=$1
   local result msg bit
   local -a dialog_items
   local -A messages=(
      [1]="Device doesn't have proper EFI system partition."
      [2]="Couldn't detect proper main system partition."
      [4]="* EFI system partition doesn't have fat filesystem!"
      [8]="* EFI system partition is too small!"
      [16]="* Main system partition is too small!"
   )

   # assemble message to descibe what was detected
   if (( status & 1 )); then
      msg+="\Z1${messages[1]}\Zn\n"
   else
      msg+="Found: \Zb${part_nodes[1]}\ZB - EFI system partition\n"
   fi
   if (( status & 2 )); then
      msg+="\Z1${messages[2]}\Zn\n"
   else
      msg+="Found: \Zb${part_nodes[2]}\ZB - Main system partition\n"
   fi
   for bit in {4,8,16} ; do
      if (( status & bit )); then
         msg+="\Z1${messages[$bit]}\Zn\n"
      fi
   done

   # options of how to proceed (based on detection)
   (( status != 0 )) || dialog_items+=("Accept" "and install on detected partitions.")
   (( status & 1 )) || dialog_items+=("Select" "main system partition manually.")
   dialog_items+=("Back" "to previous dialog.")

   # show dialog
   result=$(dialog --keep-tite --stdout --colors \
      --backtitle "$backtitle" \
      --title "Detected partitions" \
      --menu "${msg}" 10 60 6 \
      "${dialog_items[@]}"
   ) || return 2

   # process selection
   case $result in
      Accept) ;;
      Select) manual_syspart_select || return $? ;;
      Back) return 2 ;;
   esac
}

# ----------------------------------------------------------------------
# Usage: manual_syspart_select
# Purpose: Let the user pick the main system partition (the one that will
#          receive the bootloader) from a list generated with `lsblk`.
# Parameters: none
# Variables used/set:
#   backtitle          – application name.
#   device             – block device being examined.
#   sector_size        – bytes per sector (used for size comparison).
#   min_sizes[2]       – minimal acceptable size for the system partition.
#   partitions[]       – flag array; element 2 will be set to 1 on success.
#   part_nodes[]       – will receive the chosen partition node.
#   part_sizes[]       – will receive the chosen partition size (in sectors).
# Returns:
#   0 – a suitable partition was selected,
#   2 – user cancelled the dialog,
#   any other non‑zero – an error occurred while processing the choice.
# Side‑Effects:
#   * Calls `lsblk` twice (once to build the menu, once to fetch the size).
#   * Displays dialog with partition selection.
#   * May display a warning dialog if the chosen partition is too small.
# ----------------------------------------------------------------------
manual_syspart_select() {
   local result line size label
   local NAME TYPE PARTTYPENAME PARTLABEL LABEL FSTYPE
   local -a dialog_items

   # read device's partitions & build dialog items
   while IFS='' read -r line; do
      eval "$line"
      [[ $TYPE == 'part' ]] || continue
      NAME="/dev/${NAME}"
      label=$(printf "%-10s%5s|%8s %-10s|%20s" \
         "$PARTLABEL" "$SIZE" "${FSTYPE:-'no fs'}" "$LABEL" "$PARTTYPENAME")
      dialog_items+=("$NAME" "$label")
   done < <(lsblk -Pn -o NAME,TYPE,PARTTYPENAME,PARTLABEL,LABEL,FSTYPE,SIZE "$device")

   # show dialog
   result=$(dialog --keep-tite --stdout --colors \
      --backtitle "$backtitle" \
      --title "Select partition" \
      --menu "Select main system partition for bootloader installation:" \
      15 90 6 "${dialog_items[@]}" \
   ) || return 2

   # process selection
   size=$(lsblk -lnb -o SIZE "$result")
   if (( size / sector_size < min_sizes[2] )); then
      dialog --keep-tite \
         --backtitle "$backtitle" \
         --title "Warning" \
         --msgbox "${result} is to small!" 10 40
   else
      partitions[2]=1
      part_nodes[2]="$result"
   fi
}
