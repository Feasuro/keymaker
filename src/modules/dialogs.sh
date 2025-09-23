#!/bin/bash
# dialogs.sh
# Depends on: utils.sh common.sh
# Usage: source dialogs.sh and deps, in any order.
[[ -n "${DIALOGS_SH_INCLUDED:-}" ]] && return
DIALOGS_SH_INCLUDED=1

# ----------------------------------------------------------------------
# Usage: manual_dev_entry
# Purpose: Prompt the user to type a device path manually (advanced mode).
# Parameters: none
# Variables used/set:
#   BACKTITLE   – application name.
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
      --backtitle "$BACKTITLE" \
      --title "Enter device" \
      --inputbox "Enter device name (e.g. /dev/sdX)" 10 40
   )
   # shellcheck disable=SC2181
   (( $? == 0 )) || return 2

   # Check if a block device was given
   if [[ -b $result ]]; then
      devtype="$(udevadm info --query=property --no-pager --name="${result}" \
         2>/dev/null | grep '^DEVTYPE=' | cut -d= -f2)"
      # Check if it is a disk, ask for confirmation if not
      if [[ $devtype = 'disk' ]]; then
         device="$result"
         return 0
      elif dialog --keep-tite \
         --backtitle "$BACKTITLE" \
         --title "Warning" \
         --yesno "${result} appears to be ${devtype} not a disk.\nAre you sure you know what you are doing?" 10 40
         then
         device="$result"
         return 0
      fi
   else
      dialog --keep-tite \
      --backtitle "$BACKTITLE" \
      --title "Error" \
      --msgbox "${result} is not a valid block device!" 10 40
   fi
   return 2
}

# ----------------------------------------------------------------------
# Usage: pick_device
# Purpose: Show a dialog menu with detected USB devices (plus a manual‑entry
#          option) and store the chosen device in the global variable `device`.
# Parameters: none
# Variables used/set:
#   BACKTITLE           – application name.
#   message             – message for the user to display on dialog box
#   device              – selected device path (set here).
#   removable_devices[] – associative array filled by `find_devices`.
# Returns: none (updates globals and calls `handle_exit_code`).
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

   # Show menu dialog
   result=$(dialog --keep-tite --stdout \
      --backtitle "$BACKTITLE" \
      --title "Select USB Device" \
      --ok-label "Next" \
      --cancel-label "Exit" \
      --menu "$message" 20 60 6 \
      "${dialog_items[@]}"
      ) || ret=$?

   # Process selection
   if (( ret == 0 )); then
      case $result in
         other) manual_dev_entry || ret=$? ;;
         *) device="$result" ;;
      esac

      [[ -n $device ]] && log i "Chosen device -> ${device}"
   fi

   message=''
   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: pick_partitions
# Purpose: Let the user choose which partition types to create (bootloader,
#          data, persistence) via a checklist dialog.
# Parameters: none
# Globals used/set:
#   BACKTITLE    – application name.
#   message      – message for the user to display on dialog box
#   partitions[] – indexed array (size 4) of flags (0/1) indicating which
#                  partitions are selected.
# Returns: none (updates $partitions and calls `handle_exit_code`).
# Side‑Effects:
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
      --backtitle "$BACKTITLE" \
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
      fi

      set_partition_vars
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
#   BACKTITLE      – application name.
#   message        – informational text displayed at the top
#   device         – target block device (e.g. /dev/sdb)
#   sector_size    – bytes per sector (from `blockdev --getss`)
#   part_sizes[]   – current partition sizes (in sectors) modified here
#   partitions[]   – flags indicating which partitions are enabled
#   part_names[]   – human‑readable names for each partition
# Returns: none (updates $part_sizes and calls `handle_exit_code`).
# Side‑Effects:
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
      --backtitle "$BACKTITLE" \
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
      IFS=$'\n' validate_sizes $result
      ret=$(( ret + $? ))
   fi

   handle_exit_code $ret
}

# ----------------------------------------------------------------------
# Usage: confirm_format
# Purpose: Present the user with a confirmation dialog that shows the exact
#          partition layout that will be applied to the target device.
# Parameters: none (relies on globals)
# Globals used/set: none
#   BACKTITLE   – application name.
#   message     – informational text displayed on dialog box
# Returns: none (calls `handle_exit_code`).
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
   local tmpfile ret
   ret=0

   tmpfile=$(mktemp /tmp/sfdisk.XXXXXX)
   assemble_sfdisk_input > "$tmpfile"

   message=$(
      printf "\Z1\ZbProceeding will erase all data on the device!\ZB\Zn\n\n"
      format_device "$tmpfile" 'noact'
   )

   dialog --keep-tite --colors --no-collapse --extra-button \
      --backtitle "$BACKTITLE" \
      --title "Confirm partitioning scheme" \
      --yes-label "Next" \
      --no-label "Exit" \
      --extra-label "Back" \
      --yesno "${message}" 30 90 \
      || ret=$?

   # Process input
   if (( ret == 0 )); then
      if unmount_device_partitions; then
         format_device "$tmpfile"
         make_filesystems
      else
         : # TODO: dialog here
      fi
   fi

   rm -f "$tmpfile"
   handle_exit_code $ret
}
