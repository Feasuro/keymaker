#!/bin/bash
# dev_utils.sh
# Depends on: common.sh
# Usage: source dev_utils.sh and deps, in any order.
[[ -n "${DEV_UTILS_SH_INCLUDED:-}" ]] && return
DEV_UTILS_SH_INCLUDED=1

# ----------------------------------------------------------------------
# Usage: find_devices
# Purpose: Detect removable USB block devices with write permission
#          and fill the associative array.
# Parameters: none (relies on state runtime variables)
# Variables used/set:
#   removable_devices[] – associative array populated by this function.
# Returns: nothing (populates the global array).
# ----------------------------------------------------------------------
find_devices() {
   local line label
   local NAME TYPE TRAN RM RO VENDOR MODEL
   removable_devices=()

   log i "Looking for connected devices."
   while read -r line; do
      eval "$line"

      # check if it'a an usb disk, removable and write permissive
      [[ $TYPE == 'disk' ]] || continue
      [[ $TRAN == 'usb' ]] || continue
      (( RM == 1 )) || continue
      (( RO == 0 )) || continue

      # Sanitize: collapse whitespace in vendor/model string
      label="$(printf '%s %s' "$VENDOR" "$MODEL" | tr -s '[:space:]' ' ')"
      removable_devices["/dev/${NAME}"]="$label"
   done < <(lsblk -Pn -o NAME,TYPE,TRAN,RM,RO,VENDOR,MODEL)

   # Check if we have found any devices
   if [[ ${#removable_devices[@]} -eq 0 ]]; then
      message="No removable USB devices found."
      log i "${message}"
   else
      message="Choose a removable USB device:"
      log i "Found devices -> ${!removable_devices[*]}"
   fi
}

# ----------------------------------------------------------------------
# Usage: set_partition_vars
# Purpose: Derive geometry‑related variables (sector size, usable size,
#          offsets, minimal sizes in sectors, node names, etc.) based on the
#          selected device and the partition flags.
# Parameters: none
# Globals used:
#   GPT_BACKUP_SECTORS – number of sectors consumed by GPT table backup
#   PART_TABLE_OFFSET  – protected space at the beginning of disk (in bytes)
#   STORAGE_PART_NAME  – dafault GPT partition name for storage partition
#   ESP_PART_NAME      – dafault GPT partition name for esp partition
#   SYSTEM_PART_NAME   – dafault GPT partition name for system partition
#   MIN_STORAGE_SIZE   – minimal size of storage partition
#   MIN_ESP_SIZE       – minimal size of esp partition
#   MIN_SYSTEM_SIZE    – minimal size of system partition
#   MIN_FREE_SIZE      – minimal size of free space
# Variables used/set:
#   device             – selected block device (e.g. /dev/sdb)
#   sector_size        – bytes per sector (from `blockdev --getss`)
#   offset             – first usable sector (after 1 MiB)
#   usable_size        – sectors available for partitions (excluding GPT backup)
#   part_names[]       – human‑readable GPT labels
#   min_sizes[]        – minimal partition sizes (in sectors)
#   part_nodes[]       – device node names for each partition (e.g. /dev/sdb1)
#   part_sizes[]       – modified with call to `calculate_sizes`
#   partitions[]       – flags set by dialog `pick_partitions`
# Returns: (same as `calculate_sizes` called at the end)
#   0 – success,
#   1 – error,
# ----------------------------------------------------------------------
set_partition_vars() {
   local dev_size index number

   # gpt partition names
   part_names=("$STORAGE_PART_NAME" "$ESP_PART_NAME" "$SYSTEM_PART_NAME" "free space")

   if ! dev_size="$(blockdev --getsz "${device}")"; then
      log e "${device} is inaccessible"
      abort
   fi
   if ! sector_size="$(blockdev --getss "${device}")"; then
      log e "${device} is inaccessible"
      abort
   fi

   offset=$(( PART_TABLE_OFFSET / sector_size )) # first 1MiB (sectors)
   usable_size=$(( dev_size - offset - GPT_BACKUP_SECTORS )) # last sectors for gpt table backup

   # define minimal partition sizes in bytes
   min_sizes=( "$MIN_STORAGE_SIZE" "$MIN_ESP_SIZE" "$MIN_SYSTEM_SIZE" "$MIN_FREE_SIZE" )
   # convert min_sizes to sectors
   for index in "${!min_sizes[@]}"; do
      (( min_sizes[index] /= sector_size ))
   done

   part_nodes=('' '' '' '')
   number=1
   # walk through all indices but the last (free space)
   for (( index = 0; index < ${#part_nodes[@]}-1; ++index)); do
      (( partitions[index] )) || continue
      part_nodes[index]="${device}${number}"
      (( ++number ))
   done

   # populate part_sizes with default weights and 50MiB for part 2
   calculate_sizes 2 $(( 52428800 / sector_size )) 2 1
}

# ----------------------------------------------------------------------
# Usage: calculate_sizes  <w0> <fixed_sz> <w2> <w3>
# Purpose: Compute the size (in sectors) of each enabled partition based on
#          specified weights and a fixed size for the second partition.
# Parameters:
#   $1 – weight for partition 0 (storage)
#   $2 – absolute size (in sectors) for partition 1 (EFI) – fixed
#   $3 – weight for partition 2 (system)
#   $4 – weight for partition 3 (free space / persistence)
# Variables used/set:
#   usable_size   – total sectors available for flexible partitions
#   partitions[]  – flag array (0 = disabled, 1 = enabled)
#   part_sizes[]  – resulting sizes (in sectors) for each partition
# Returns:
#   0 – success,
#   1 – no flexible partitions enabled (ratio = 0),
# ----------------------------------------------------------------------
calculate_sizes() {
   local available ratio remainder index

   available=$(( usable_size - $2 ))
    ratio=$(( $1 * partitions[0] + $3 * partitions[2] + $4 * partitions[3] ))

   if (( ratio == 0 )); then
      log d "No partitions enabled (ratio = 0)."
      return 1
   fi

   part_sizes[0]=$(( $1 * available * partitions[0] / ratio ))
   part_sizes[1]=$(( $2 * partitions[1] ))
   part_sizes[2]=$(( $3 * available * partitions[2] / ratio ))
   part_sizes[3]=$(( $4 * available * partitions[3] / ratio ))

   # Distribute any remainder left from integer division
   remainder=$(( available - part_sizes[0] - part_sizes[2] - part_sizes[3] ))
   index=${#partitions[@]}
   while (( remainder > 0 )); do
      if (( partitions[index] && index != 1 )); then
            (( ++part_sizes[index] ))
            (( remainder-- ))
      fi
      (( index = ++index % ${#partitions[@]} ))
   done

   log d "
   available  = ${available} sectors
   ratio      = ${ratio}
   remainder  = ${remainder} sectors
   part_sizes = (${part_sizes[0]}, ${part_sizes[1]}, ${part_sizes[2]}, ${part_sizes[3]})
   sum(flex)  = $((part_sizes[0]+part_sizes[2]+part_sizes[3])) (should equal available)"
}

# ----------------------------------------------------------------------
# Usage: validate_sizes  <size1> <size2> <size3> <size4>
# Purpose: Validate user‑entered IEC size strings, enforce minimum sizes,
#          and adjust the free‑space partition if necessary.
# Parameters:
#   $1 $2 $3 $4 – IEC strings supplied by the user for each enabled partition.
#                 (e.g. "2Gi", "500Mi", …)
# Variables used/set:
#   message       – diagnostic/message string displayed later.
#   sector_size   – bytes per sector.
#   usable_size   – total sectors available.
#   partitions[]  – flag array.
#   part_sizes[]  – current sizes (sectors).
#   min_sizes[]   – minimal allowed sizes (sectors).
#   part_names[]  – human‑readable names (for messages).
# Returns:
#   0 – all sizes accepted as‑is,
#   2 – sizes were adjusted; caller should treat this as “changes made”.
# ----------------------------------------------------------------------
validate_sizes() {
   local sum index size accepted
   local -a new_sizes
   message=''
   accepted=1

   # assign new_sizes array with user input
   for index in "${!partitions[@]}"; do
      if (( ! partitions[index] )); then
         new_sizes+=(0)
         continue
      fi
      # check if iec strings match
      [ "$1" == "$(numfmt --to=iec-i $((part_sizes[index] * sector_size)))" ] || accepted=0

      new_sizes+=( $(( $(numfmt --from=iec-i "$1") / sector_size )) )
      shift
   done

   log d "
   part_sizes = ${part_sizes[*]}
   new_sizes  = ${new_sizes[*]}
   accepted   = ${accepted}"

   # values were correct and accepted by user
   (( accepted )) && return 0

   # check if sizes are greater than minimum
   for index in "${!partitions[@]}"; do
      if (( partitions[index] && new_sizes[index] < min_sizes[index])); then
         message+="\Z1${part_names[index]} was to small!\Zn\n"
         new_sizes[index]=${min_sizes[index]}
      fi
   done

   # calculate sum of partitions' sizes
   sum=0
   for size in "${new_sizes[@]}"; do
      ((sum+=size))
   done

   # if free space was chosen we try to adjust it
   if (( partitions[3] )); then
      if (( sum > usable_size && sum - new_sizes[3] < usable_size - min_sizes[3] )); then
         [[ -z $DEBUG || $DEBUG == 0 ]] || echo "   adjusted free space down" >&2
         (( new_sizes[3] -= sum - usable_size ))
         sum=$usable_size
      elif (( sum < usable_size )); then
         [[ -z $DEBUG || $DEBUG == 0 ]] || echo "   adjusted free space up" >&2
         (( new_sizes[3] += usable_size - sum ))
         sum=$usable_size
      fi
   fi

   # new sizes are correct
   if (( sum == usable_size )); then
      message+="\Z2Press next to accept changes.\Zn\n"
      part_sizes=("${new_sizes[@]}")
      return 2
   fi

   # if partitions don't fit recalculate sizes proportionally
   message+="\Z1Partitions scaled to fit disk size!\Zn\n"
   # shellcheck disable=SC2068
   calculate_sizes ${new_sizes[@]}
   return 2
}

# -------------------------------------------------
# Usage: unmount_device_partitions
# Purpose: Ensures every partition on a given block device is unmounted.
# Parameters: none (relies on globals)
# Variables used/set:
#   device          – the block device (e.g. /dev/sdb)
# Return codes:
#   0 – all partitions were already unmounted or were successfully unmounted
#   1 – one or more partitions could not be unmounted
# -------------------------------------------------
unmount_partitions() {
   local ret part
   ret=0

   # Iterate over each partition and unmount it
   while read -r part; do
      part="/dev/${part}"
      # check if already unmounted
      findmnt "$part" >/dev/null || {
         log d "${part} not mounted"
         continue
      }

      if umount "$part" 2>/dev/null; then
         log i "Unmounted ${part}."
      else
         log w "Failed to unmount ${part}"
         ret=1
      fi
   done < <(lsblk -ln -o NAME "$device")

   return $ret
}

# ----------------------------------------------------------------------
# Usage: assemble_sfdisk_input
# Purpose: Construct complete sfdisk input that describes the
#          partition table to be written to the target device.
# Parameters: none (relies on globals)
# Variables used/set:
#   device          – the block device (e.g. /dev/sdb)
#   sector_size     – bytes per sector (from `blockdev --getss`)
#   offset          – first usable sector (after the protective MBR)
#   usable_size     – total sectors available.
#   partitions[]    – flags indicating which partitions are enabled
#   part_sizes[]    – sizes of each partition in sectors
#   part_names[]    – human‑readable GPT partition labels
#   part_nodes[]    – device node names for each partition (e.g. /dev/sdb1)
# Returns: none (does not return a status code.)
# Side‑Effects: Prints the fully‑assembled sfdisk command to `stdout`.
# ----------------------------------------------------------------------
assemble_sfdisk_input() {
   local start index guid

   # tell sfdisk we want a fresh GPT table
   cat << EOF
label: gpt
device: ${device}
unit: sectors
sector-size: ${sector_size}
first-lba: ${offset}
last-lba: $(( offset + usable_size - 1 ))

EOF

   # Start allocating partitions after offset (first MiB)
   start=$offset

   for index in "${!partitions[@]}"; do
      (( partitions[index] )) || continue # skip if flag == 0

      # Choose the proper GPT type GUID
      case $index in
         0) guid="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7" ;; # Microsoft basic data
         1) guid="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ;; # EFI System Partition
         2) guid="0fc63daf-8483-4772-8e79-3d69d8477de4" ;; # Linux filesystem
         3) continue ;; # free space
      esac

      # Print the partition definition line
      printf '%s:start=%s,size=%s,type=%s,name="%s"\n' "${part_nodes[$index]}" \
         "$start" "${part_sizes[$index]}" "$guid" "${part_names[$index]}"

      (( start += part_sizes[index] ))
   done
}

# ----------------------------------------------------------------------
# Usage: format_device <input> [<noact>]
# Purpose: Apply a partition layout to the target block device using `sfdisk`.  
#          Function builds a command line that feeds supplied input to `sfdisk`.
# Parameters:
#   $1 – A string containing the sfdisk input specification.
#   $2 – Optional mode flag. Value `noact` causes a dry‑run that
#        prints what would be done without modifying the disk.
# Variables used/set:
#   DEBUG   – when set, the command and sfdisk output is print to stderr.
#   device  – the block device to be partitioned (e.g. /dev/sdb).
# Returns: the exit status of the executed `sfdisk` command.
#   0        – Success.
#   non‑zero – Failure. In case of a non‑zero status the function calls
#              `abort`, which terminates the script with status 1.
# Side‑Effects:
#   * Executes the external `sfdisk` program, which writes a new partition
#     table to `$device` (unless `--no-act` is used).
#   * May write sfdisk output to standard error when `$DEBUG` is enabled.
#   * Calls `abort` on error, which removes temporary files and exits.
# ----------------------------------------------------------------------
format_device() {
   local input="$1"
   local -a cmd

   cmd=( sfdisk --wipe always --wipe-partitions always "$device" "<${input}" )

   if [[ ${2:-} == 'noact' ]]; then
      cmd+=( --no-act '2>&1' )
   elif [ "$DEBUG" ]; then
      log i "Executing -> ${cmd[*]}"
   else
      cmd+=( '>/dev/null' )
      log i "Executing -> ${cmd[*]}"
   fi

   # shellcheck disable=SC2294
   eval "${cmd[*]}"
}

# ----------------------------------------------------------------------
# Usage: make_filesystems
# Purpose: Format each partition that was created with the appropriate
#          filesystem type and label.
# Parameters: none (relies on globals)
# Variables used/set:
#   device               – the target block device (e.g. /dev/sdb)
#   part_nodes[]         – device node names for each partition (e.g. /dev/sdb1)
#   removable_devices[]  – associative array mapping a device path to a
#                          human‑readable label
# Returns: none; any non‑zero exit status from `mkfs.*` will cause the script
#          to terminate via the surrounding `abort` logic.
# Side‑Effects:
#   * Executes external formatting utilities: `mkfs.exfat`, `mkfs.fat` and `mkfs.ext4`
# ----------------------------------------------------------------------
make_filesystems() {
   local index label

   for index in "${!part_nodes[@]}"; do
      [[ -n ${part_nodes[index]} ]] || continue
      case $index in
         0)
            label=${removable_devices[$device]:-'Data'}
            log i "Creating exFAT filesystem on ${part_nodes[$index]}"
            mkfs.exfat -L "${label%% *}" "${part_nodes[$index]}"
            ;; # storage
         1)
            log i "Creating FAT filesystem on ${part_nodes[$index]}"
            mkfs.fat -n 'EFI' "${part_nodes[$index]}"
            ;; # esp
         2)
            log i "Creating ext4 filesystem on ${part_nodes[$index]}"
            mkfs.ext4 -F -L 'casper-rw' "${part_nodes[$index]}"
            ;; # system
         3)
            continue
            ;; # free space
      esac
   done
}
