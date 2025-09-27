#!/bin/bash
# step_dialogs.sh
# Depends on: helper_dialogs.sh dev_utils.sh boot_utils.sh common.sh
# Usage: source step_dialogs.sh and deps, in any order.
[[ -n "${STEP_DIALOGS_SH_INCLUDED:-}" ]] && return
STEP_DIALOGS_SH_INCLUDED=1

# ----------------------------------------------------------------------
# Usage: pick_device
# Purpose: Show a dialog menu with detected USB devices (plus a manual‑entry
#          option) and store the chosen device in the global variable `device`.
# Parameters: none
# Variables used/set:
#   backtitle           – application name.
#   message             – message for the user to display on dialog box
#   device              – selected device path (set here).
#   removable_devices[] – associative array filled by `find_devices`.
# Returns: 0 (calls `handle_exit_code`).
# Side‑Effects:
#   * Displays `dialog` form where user can pick device to use.
#   * Prints comunicates to stderr.
# ----------------------------------------------------------------------
pick_device() {
   local result ret dev
   local -a dialog_items
   ret=0

   device=''
   find_devices

   # Build dialog menu items
   dialog_items=()
   for dev in "${!removable_devices[@]}"; do
      dialog_items+=("$dev" "${removable_devices[$dev]}")
   done
   dialog_items+=("other" "Specify device manually (advanced)")
   dialog_items+=("rescan" "Repeat device search")

   # Show menu dialog
   result=$(dialog --keep-tite --stdout \
      --backtitle "$backtitle" \
      --title "Select USB Device" \
      --ok-label "Next" \
      --cancel-label "Exit" \
      --menu "$message" 20 60 6 \
      "${dialog_items[@]}"
      ) || ret=$?

   # Process selection
   if (( ret == 0 )); then
      case $result in
         rescan) ret=2 ;;
         other) manual_dev_entry || ret=$? ;;
         *) device="$result" ;;
      esac

      [[ -n $device ]] && log i "Chosen device -> ${device}"
   fi

   message=''
   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: ask_format_or_keep
# Purpose: Show a dialog to choose if device should be formatted or current
#          partition layout should be kept.
# Parameters: none
# Variables used/set:
#   backtitle           – application name.
#   SYSTEM_PART_NAME    – GPT partition name for system partition.
#   step                – current wizard step.
# Returns: 0 (calls `handle_exit_code`).
# Side‑Effects: Displays `dialog` where user can choose how to proceed.
# ----------------------------------------------------------------------
ask_format_or_keep() {
   local msg result status ret
   local -a dialog_items
   ret=0

   dialog_items=("Format" "my device (all data will be lost).")
   dialog_items+=("Keep" "my device partition layout.")
   msg="To make device bootable, keybuilder needs at least:
   * EFI system partition (fat)
   * Main installation partition '${SYSTEM_PART_NAME}'"

   # Show dialog
   result=$(dialog --keep-tite --stdout --colors --extra-button \
      --backtitle "$backtitle" \
      --title "Choose format action" \
      --ok-label "Next" \
      --cancel-label "Exit" \
      --extra-label "Back" \
      --menu "${msg}" 20 60 6 \
      "${dialog_items[@]}"
   ) || ret=$?

   # Process selection
   if [[ $ret -eq 0 && $result == "Keep" ]]; then
      status=0
      detect_target_partitions || status=$?
      confirm_detected_partitions $status || ret=$?
      (( ret )) || (( step+=3 )) # skip 3 steps if 'Keep' is confirmed
   fi

   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: pick_partitions
# Purpose: Let the user choose which partition types to create (bootloader,
#          data, persistence) via a checklist dialog.
# Parameters: none
# Globals used/set:
#   backtitle    – application name.
#   message      – message for the user to display on dialog box
#   partitions[] – indexed array (size 4) of flags (0/1) indicating which
#                  partitions are selected.
# Returns: 0 (calls `handle_exit_code`).
# Side‑Effects:
#   * Updates partitions[] array
#   * Displays `dialog` where the user can choose partitions to enable.
#   * Calls `set_partition_vars` that manipulates several nonlocal variables
# ----------------------------------------------------------------------
pick_partitions() {
   local result ret opt
   local -a dialog_items
   ret=0

   # Build dialog items
   dialog_items=(1 "Create partitions for bootloader and iso files" on)
   dialog_items+=(2 "Create additional partition for data storage" off)
   dialog_items+=(3 "Leave space for persistence partition(s)" off)

   # Show dialog
   result=$(dialog --keep-tite --stdout --colors --extra-button \
      --backtitle "$backtitle" \
      --title "Select options" \
      --ok-label "Next" \
      --cancel-label "Exit" \
      --extra-label "Back" \
      --checklist "${message}Choose partitions to create:" 20 60 6 \
      "${dialog_items[@]}"
   ) || ret=$?

   # Process selection
   if (( ret == 0 )); then
      message=''
      partitions=(0 0 0 0)
      for opt in $result; do
         case $opt in
            1) partitions[1]=1; partitions[2]=1 ;; # efi+system
            2) partitions[0]=1 ;; # storage
            3) partitions[3]=1 ;; # free space
         esac
      done

      if (( partitions[0] + partitions[1] + partitions[2] == 0 )); then
         message="\Z1No partitions to create!\Zn\n"
         ret=2
      else
         set_partition_vars
      fi
   fi

   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: set_partitions_size
# Purpose: Interactively ask user via `dialog` form, to edit the sizes of
#          the enabled partitions. Function gathers raw user input,
#          validates it, and updates global `part_sizes` array accordingly.
# Parameters: none (relies on globals)
# Globals used/set:
#   backtitle      – application name.
#   message        – informational text displayed at the top
#   device         – target block device (e.g. /dev/sdb)
#   sector_size    – bytes per sector (from `blockdev --getss`)
#   part_sizes[]   – current partition sizes (in sectors) modified here
#   partitions[]   – flags indicating which partitions are enabled
#   part_names[]   – human‑readable names for each partition
# Returns: 0 (calls `handle_exit_code`).
# Side‑Effects:
#   * Updates part_sizes[] array
#   * Displays `dialog` form where the user can edit partition sizes.
# ----------------------------------------------------------------------
set_partitions_size() {
   local result count size ret index
   local -a dialog_items
   ret=0

   # Build dialog items
   dialog_items=()
   count=0
   for index in "${!partitions[@]}"; do
      if (( partitions[index] )); then
         (( ++count ))
         size=$(numfmt --to=iec-i $((part_sizes[index] * sector_size)))
         dialog_items+=("${device}${count} ${part_names[$index]}" \
            "$count" 1 "$size" "$count" 30 15 0)
      fi
   done
   # Remove /dev/sdxN before free space
   (( partitions[3] )) && dialog_items[-8]="${part_names[3]}"

   # Show dialog
   result=$(dialog --keep-tite --extra-button --colors --stdout \
      --backtitle "$backtitle" \
      --title "Adjust partition sizes" \
      --ok-label "Next" \
      --cancel-label "Exit" \
      --extra-label "Back" \
      --form "${message}The following partitions will be created:" \
      20 60 4 "${dialog_items[@]}"
   ) || ret=$?

   # Process input
   if (( ret == 0 )); then
      # shellcheck disable=SC2086
      validate_sizes $result || (( ret += $? ))
   fi

   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: confirm_format
# Purpose: Present the user with a confirmation dialog that shows the exact
#          partition layout that will be applied to the target device.
# Parameters: none (relies on globals)
# Globals used/set: none
#   backtitle   – application name.
#   message     – informational text displayed on dialog box
# Returns: 0 (calls `handle_exit_code`).
# Side‑Effects:
#   * Shows a `dialog` window that warns the user about data loss.
#   * Creates a temporary file with partition description.
#   * Calls `format_device` twice:
#        – first with `noact` to perform a dry‑run for display,
#        – second to actually write the partition table.    
#   * Calls `make_filesystems` to format the newly created partitions.
#   * Deletes the temporary file before exiting.
# ----------------------------------------------------------------------
confirm_format() {
   local msg tmpfile ret
   ret=0

   # ensure nothing is mounted before proceeding
   unmount_partitions || {
      request_manual_unmount || app_exit
      return $ret
   }

   tmpfile=$(mktemp /tmp/sfdisk.XXXXXX)
   assemble_sfdisk_input > "$tmpfile"

   # show the user what would be done
   msg=$(
      printf "\Z1\ZbProceeding will erase all data on the device!\ZB\Zn\n\n"
      format_device "$tmpfile" 'noact'
   )

   # show the confirmation dialog
   dialog --keep-tite --colors --no-collapse --extra-button \
      --backtitle "$backtitle" \
      --title "Confirm partitioning scheme" \
      --yes-label "Next" \
      --no-label "Exit" \
      --extra-label "Back" \
      --yesno "${msg}" 30 90 \
      || ret=$?

   # Process input
   if (( ret == 0 )); then
      format_device "$tmpfile"
      make_filesystems
   fi

   rm -f "$tmpfile"
   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: install_components
# Purpose: Show dialog with components to install along with the bootloader,
#          then performs installation according to user selection.
# Parameters: none (relies on globals)
# Globals used/set: none
#   backtitle   – application name.
# Returns: 0 (calls `handle_exit_code`).
# Side‑Effects:
#   * Calls `check_uefi` and terminates script if it fails.
#   * Shows a `dialog` window.
#   * Calls `install_bootloader` to perform actual installation.
# ----------------------------------------------------------------------
install_components() {
   local ret
   ret=0

   check_uefi || abort

   # show the dialog
   dialog --keep-tite --extra-button \
      --backtitle "$backtitle" \
      --title "Choose components to install" \
      --yes-label "Next" \
      --no-label "Exit" \
      --extra-label "Back" \
      --yesno "Hit enter to install GRUB" 20 60 \
      || ret=$?

   # Process input
   if (( ret == 0 )); then
      install_bootloader
   fi

   handle_exit_code $ret
}