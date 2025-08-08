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
    menu_items=()
    for dev in "${!removable_devices[@]}"; do
        menu_items+=("$dev" "${removable_devices[$dev]}")
    done
    menu_items+=("other" "Specify device manually (advanced)")
    menu_items+=("cancel" "Exit program")

    # Show menu dialog
    while true; do
        selected=$(dialog --keep-tite --no-cancel --stdout \
            --backtitle "$backtitle" \
            --title "Select USB Device" \
            --menu "Choose a removable USB device:" 15 60 6 \
            "${menu_items[@]}"
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

dev_size="$(sudo blockdev --getsize64 "${device}")"

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
    echo "Partitioning"
else
    echo "Not Partitioning. Exiting."
    exit 0
fi
