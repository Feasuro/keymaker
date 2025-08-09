#!/bin/bash

backtitle="Keymaker"

echo "Looking for connected devices."
declare -A removable_devices

# Find connected removable devices
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

function manual_entry() {
    local result
    result=$(dialog --keep-tite --stdout \
        --backtitle "$backtitle" \
        --title "Enter device" \
        --inputbox "Enter device name (e.g. /dev/sdX)" 10 40
    )

    if [ -b "$result" ]; then
        devtype="$(udevadm info --query=property --no-pager --name="${result}" \
            2>/dev/null | grep '^DEVTYPE=' | cut -d= -f2)"
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

device=""
# Check if we have any devices
if [[ ${#removable_devices[@]} -eq 0 ]]; then
    echo "No removable devices found"

    while true; do
        if dialog --keep-tite \
            --backtitle "$backtitle" \
            --title "No removable USB devices found" \
            --yesno "Would you like to specify device manually? (advanced)" 7 40
        then
            device="$(manual_entry)"
        else
            echo "Exiting."
            exit 0
        fi

        # Exit loop if device was chosen
        if [ -n "$device" ]; then
            echo "Chosen device: ${device}"
            break
        fi
    done
else
    echo "Found devices:" "${!removable_devices[@]}"

    # Build dialog menu arguments
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
            --title "Select USB Device" \
            --menu "Choose a removable USB device:" 15 60 6 \
            "${dialog_items[@]}"
            )

        case $selected in
            cancel)
                echo "Exiting"
                exit 0;;
            other)
                device="$(manual_entry)";;
            *)
                device="$selected";;
        esac

        # Exit loop if device was chosen properly
        if [ -n "$device" ]; then
            echo "Chosen device: ${device}"
            break
        fi
    done
fi

function calculate_sizes() {
    dev_size=$1
    pt_sys=$2
    pt_sto=$3
    pt_emp=$4

    ratio=$((2*pt_sys+2*pt_sto+pt_emp))
    chunk=$(((dev_size - 51*1024*1024)/ratio))

    size_sys=$(numfmt --to=iec-i $((2*chunk*pt_sys)))
    size_efi=$(numfmt --to=iec-i $((50*1024*1024)))
    size_sto=$(numfmt --to=iec-i $((2*chunk*pt_sto)))
    size_emp=$(numfmt --to=iec-i $((chunk*pt_emp)))

    echo "${size_sys} ${size_efi} ${size_sto} ${size_emp}"
}

dev_size="$(sudo blockdev --getsize64 "${device}")"
part_system=0
part_efi=1
part_storage=0
part_empty=0

msg="$(cat << EOF
Would you like to create new partition table?
\Z1WARNING!\Zn It will erase all data on the device.
EOF
)"

if dialog --keep-tite --colors \
    --backtitle "$backtitle" \
    --title "Partitioning" \
    --yesno "${msg}" 0 0
then

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
            1) part_system=1 ;;
            2) part_storage=1 ;;
            3) part_empty=1 ;;
        esac
    done

    dialog_items=()
    count=0
    set -- $(calculate_sizes "$dev_size" "$part_system" "$part_storage" "$part_empty")
    for part in "$part_system" "$part_efi" "$part_storage" "$part_empty"; do
        if [ $part -ne 0 ]; then
            ((count+=1))
            dialog_items+=("${device}${count}" "$count" 1 "${!count}" "$count" 30 15 0)
        fi
    done

    dialog --keep-tite \
    --backtitle "$backtitle" \
    --title "Confirm " \
    --form "The following partitions will be created:" 20 60 4 \
    "${dialog_items[@]}"

else
    echo "Not Partitioning. Exiting."
    exit 0
fi
