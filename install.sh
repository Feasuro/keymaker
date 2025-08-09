#!/bin/bash

backtitle="Keymaker"

# exit 9 will exit app also from a subshell
set -E
trap '[ "$?" -ne 9 ] || app_exit' ERR
trap 'abort' INT

function abort() {
    echo "Application aborted."
    exit 1
}

function app_exit() {
    echo "Exiting."
    exit 0
}

function find_devices() {
    local id_bus id_vendor id_model devname
    for sys_path in /sys/block/*; do
        # Reset variables for each iteration
        unset id_bus id_vendor id_model devname
        # Parse known keys
        while IFS='=' read -r key value; do
            case "$key" in
                ID_BUS) id_bus="$value" ;;
                ID_VENDOR) id_vendor="$value" ;;
                ID_MODEL) id_model="$value" ;;
                DEVNAME) devname="$value" ;;
            esac
        done < <(udevadm info --query=property --no-pager --path="$sys_path" 2>/dev/null)
        # Skip if it's not a USB device or devname is missing
        if [[ "$id_bus" != "usb" || -z "$devname" ]]; then
            continue
        fi
        # Sanitize: collapse whitespace in vendor/model string
        label="$(echo "$id_vendor $id_model" | tr -s '[:space:]' ' ')"
        # Only store safe device names (match /dev/sd[a-z]*)
        if [[ "$devname" =~ ^/dev/sd[a-z]+$ ]]; then
            removable_devices["$devname"]="$label"
        fi
    done
}

function manual_dev_entry() {
    local result devtype
    result=$(dialog --keep-tite --stdout \
        --backtitle "$backtitle" \
        --title "Enter device" \
        --inputbox "Enter device name (e.g. /dev/sdX)" 10 40
    )
    [ "$?" -eq 0 ] || return 1

    # Check if a block device was given
    if [ -b "$result" ]; then
        devtype="$(udevadm info --query=property --no-pager --name="${result}" \
            2>/dev/null | grep '^DEVTYPE=' | cut -d= -f2)"
        # Check if it is a disk, ask for confirmation if not
        if [ "$devtype" = "disk" ]; then
            echo "$result"
            return 0
        elif dialog --keep-tite --stdout \
            --backtitle "$backtitle" \
            --title "Warning" \
            --yesno "${result} appears to be ${devtype} not a disk.\nAre you sure you know what you are doing?" 10 40
            then
            echo "$result"
            return 0
        fi
    else
        dialog --keep-tite --stdout \
        --backtitle "$backtitle" \
        --title "Error" \
        --msgbox "${result} is not a valid block device!" 10 40
    fi
    return 1
}

function pick_device() {
    local selected device message dialog_items
    message="$1"
    # Build dialog menu items
    dialog_items=()
    for dev in "${!removable_devices[@]}"; do
        dialog_items+=("$dev" "${removable_devices[$dev]}")
    done
    dialog_items+=("other" "Specify device manually (advanced)")
    dialog_items+=("cancel" "Exit program")

    # Show menu dialog
    while true; do
        selected=$(dialog --keep-tite --no-cancel --stdout \
            --backtitle "$backtitle" \
            --title "Select USB Device." \
            --menu "$message" 15 60 6 \
            "${dialog_items[@]}"
            )

        # Process selection
        case $selected in
            cancel)
                exit 9;;
            other)
                device="$(manual_dev_entry)";;
            *)
                device="$selected";;
        esac

        # Exit loop if device was chosen
        if [ -n "$device" ]; then
            echo "$device"
            return 0
        fi
    done
}

function pick_partitions() {
    local part_sys part_sto part_emp choices dialog_items
    part_sys=0
    part_sto=0
    part_emp=0

    dialog_items=(1 "Create partitions for bootloader and iso files" on)
    dialog_items+=(2 "Create additional partition for data storage" off)
    dialog_items+=(3 "Leave space for persistence partition(s)" off)

    choices=$(dialog --keep-tite --no-cancel --stdout \
        --backtitle "$backtitle" \
        --title "Select options" \
        --checklist "Choose a removable USB device:" 15 60 6 \
        "${dialog_items[@]}"
    )

    for opt in $choices; do
        case $opt in
            1) part_sys=1 ;;
            2) part_sto=1 ;;
            3) part_emp=1 ;;
        esac
    done

    echo "${part_sys} ${part_sto} ${part_emp}"
}

function calculate_sizes() {
    local dev_size part_sys part_sto part_emp
    dev_size=$1
    part_sys=$2
    part_sto=$3
    part_emp=$4
    local ratio chunk
    local size_sys size_efi size_sto size_emp

    # Default proportions:
    ratio=$((2*part_sys+2*part_sto+part_emp))
    chunk=$(((dev_size - 51*1024*1024)/ratio))

    size_sys=$(numfmt --to=iec-i $((2*chunk*part_sys)))
    size_efi=$(numfmt --to=iec-i $((50*1024*1024)))
    size_sto=$(numfmt --to=iec-i $((2*chunk*part_sto)))
    size_emp=$(numfmt --to=iec-i $((chunk*part_emp)))

    echo "${size_sys} ${size_efi} ${size_sto} ${size_emp}"
}

function partitions_setup() {
    local part_sys part_efi part_sto part_emp
    local dev_size dialog_items count
    part_efi=1

    # User picks which partitions are to make
    read -r part_sys part_sto part_emp < <(pick_partitions)

    dev_size="$(sudo blockdev --getsize64 "${device}")"

    # Build dialog items
    dialog_items=()
    count=0
    set -- $(calculate_sizes "$dev_size" "$part_sys" "$part_sto" "$part_emp")
    for part in "$part_sys" "$part_efi" "$part_sto" "$part_emp"; do
        if [ "$part" -ne 0 ]; then
            ((count+=1))
            dialog_items+=("${device}${count}" "$count" 1 "${!count}" "$count" 30 15 0)
        fi
    done

    dialog --keep-tite \
    --backtitle "$backtitle" \
    --title "Confirm " \
    --form "The following partitions will be created:" 20 60 4 \
    "${dialog_items[@]}"
}

clear
declare -A removable_devices
echo "Looking for connected devices."
find_devices

message=""
# Check if we have any devices
if [[ ${#removable_devices[@]} -eq 0 ]]; then
    message="No removable USB devices found."
    echo "$message"
else
    message="Choose a removable USB device:"
    echo "Found devices:" "${!removable_devices[@]}"
fi
device=$(pick_device "$message")
echo "Chosen device: ${device}"


message="$(cat << EOF
Would you like to create new partition table?
\Z1WARNING!\Zn It will erase all data on the device.
EOF
)"

if dialog --keep-tite --colors \
    --backtitle "$backtitle" \
    --title "Partitioning" \
    --yesno "${message}" 0 0
then
    partitions_setup
else
    echo "Not implemented"
    app_exit
fi
