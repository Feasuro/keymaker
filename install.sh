#!/bin/bash

echo "Starting the script"
backtitle="Keymaker"

declare -A removable_devices

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

# Check if we have any devices
if [[ ${#removable_devices[@]} -eq 0 ]]; then
    if dialog --keep-tite \
        --backtitle "$backtitle" \
        --title "No removable USB devices found" \
        --yesno "Would you like to specify device manually? (advanced)" 7 40
    then
        exit
    else
        exit 0
    fi
fi

# Build dialog menu arguments
menu_items=()
for dev in "${!removable_devices[@]}"; do
    menu_items+=("$dev" "${removable_devices[$dev]}")
done
menu_items+=("other" "Specify device manually (advanced)")
menu_items+=("cancel" "Exit program")

# Show dialog menu
selected=$(dialog --keep-tite --stdout \
    --backtitle "$backtitle" \
    --title "Select USB Device" \
    --menu "Choose a removable USB device:" 15 60 6 \
    "${menu_items[@]}"
    )

if [[ -n "$selected" ]]; then
    echo "You selected: $selected"
else
    echo "No selection made."
fi
