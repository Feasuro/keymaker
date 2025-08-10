#!/bin/bash

backtitle="Keymaker"

trap 'abort' INT

function abort() {
    echo "Application aborted."
    exit 1
}

function app_exit() {
    echo "Exiting."
    exit 0
}

function handle_exit_code() {
    # Actions of dialog buttons
    case $1 in
        0) ((step+=1)) ;;
        1) app_exit ;;
        2) echo "dupa dupa";;
        3) ((step-=1)) ;;
        *) 
            echo "Error: Unknown exit code - ${1}"
            abort
        ;;
    esac
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

    # Show dialog
    result=$(dialog --keep-tite --stdout \
        --backtitle "$backtitle" \
        --title "Enter device" \
        --inputbox "Enter device name (e.g. /dev/sdX)" 10 40
    )
    [ "$?" -eq 0 ] || return 2

    # Check if a block device was given
    if [ -b "$result" ]; then
        devtype="$(udevadm info --query=property --no-pager --name="${result}" \
            2>/dev/null | grep '^DEVTYPE=' | cut -d= -f2)"
        # Check if it is a disk, ask for confirmation if not
        if [ "$devtype" = "disk" ]; then
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
        --title "Error" \
        --msgbox "${result} is not a valid block device!" 10 40
    fi
    return 2
}

function pick_device() {
    local result message dialog_items ret
    message="$1"

    # Build dialog menu items
    dialog_items=()
    for dev in "${!removable_devices[@]}"; do
        dialog_items+=("$dev" "${removable_devices[$dev]}")
    done
    dialog_items+=("other" "Specify device manually (advanced)")

    # Show menu dialog
    result=$(dialog --keep-tite --stdout \
        --backtitle "$backtitle" \
        --title "Select USB Device" \
        --ok-label "Next" \
        --cancel-label "Exit" \
        --menu "$message" 15 60 6 \
        "${dialog_items[@]}"
        )

    ret=$?
    # Process selection
    if [ $ret -eq 0 ]; then
        case $result in
            other)
                manual_dev_entry ;;
            *)
                device="$result" ;;
        esac

        [ -n "$device" ] || return 2
    fi

    echo "Chosen device: ${device}"
    return $ret
}

function pick_partitions() {
    local result dialog_items ret

    # Build dialog items
    dialog_items=(1 "Create partitions for bootloader and iso files" on)
    dialog_items+=(2 "Create additional partition for data storage" off)
    dialog_items+=(3 "Leave space for persistence partition(s)" off)

    # Show dialog
    result=$(dialog --keep-tite --stdout --extra-button \
        --backtitle "$backtitle" \
        --title "Select options" \
        --ok-label "Next" \
        --cancel-label "Exit" \
        --extra-label "Back" \
        --checklist "Choose partitions to create:" 15 60 6 \
        "${dialog_items[@]}"
    )

    ret=$?
    # Process selection
    if [ $ret -eq 0 ]; then
        partitions=(0 1 0 0)
        for opt in $result; do
            case $opt in
                1) partitions[2]=1 ;; # system
                2) partitions[0]=1 ;; # storage
                3) partitions[3]=1 ;; # free space
            esac
        done
    fi

    return $ret
}

function calculate_sizes() {
    local ratio chunk
    # TODO: get rid of sudo
    dev_size="$(sudo blockdev --getsize64 "${1}")"

    # Default proportions:
    ratio=$((2*partitions[0]+2*partitions[2]+partitions[3]))
    chunk=$(((dev_size - 51*1024*1024)/ratio))

    part_sizes[0]=$(numfmt --to=iec-i $((2*chunk*partitions[0])))
    part_sizes[1]=$(numfmt --to=iec-i $((50*1024*1024*partitions[1])))
    part_sizes[2]=$(numfmt --to=iec-i $((2*chunk*partitions[2])))
    part_sizes[3]=$(numfmt --to=iec-i $((chunk*partitions[3])))
}

function adjust_sizes() {
    echo "Not Implemented"
}

function partitions_size() {
    local result dialog_items count index ret

    # Build dialog items
    dialog_items=()
    count=0
    for index in {0..3}; do
        if [ "${partitions[$index]}" -ne 0 ]; then
            ((count+=1))
            dialog_items+=("${device}${count} ${part_names[$index]}" \
                "$count" 1 "${part_sizes[$index]}" "$count" 30 15 0)
        fi
    done
    # Remove /dev/sdxN before free space
    [ "${partitions[3]}" -ne 0 ] && dialog_items[-8]="${part_names[3]}"

    # Show dialog
    result=$(dialog --keep-tite --extra-button --stdout \
        --backtitle "$backtitle" \
        --title "Adjust partition sizes" \
        --ok-label "Next" \
        --cancel-label "Exit" \
        --extra-label "Back" \
        --form "The following partitions will be created:" 20 60 4 \
        "${dialog_items[@]}"
    )

    ret=$?
    # Process input
    if [ $ret -eq 0 ]; then
        echo "DEBUG: ${result}"
    fi

    return $ret
}

function main() {
    clear
    declare step=1
    declare -A removable_devices
    declare device dev_size
    declare -a partitions part_sizes
    declare -a part_names=("storage" "esp" "system" "free space")
    local message

    while true; do
        case $step in
            1)
                echo "Looking for connected devices."
                find_devices

                # Check if we have any devices
                if [[ ${#removable_devices[@]} -eq 0 ]]; then
                    message="No removable USB devices found."
                    echo "$message"
                else
                    message="Choose a removable USB device:"
                    echo "Found devices:" "${!removable_devices[@]}"
                fi

                # Show dialog to choose a device
                pick_device "$message"
                handle_exit_code $?
            ;;
            2)
                pick_partitions
                handle_exit_code $?
                calculate_sizes "$device"
            ;;
            3)
                partitions_size
                handle_exit_code $?
            ;;
            4)
                echo "Finished."
                break
            ;;
        esac
    done
}

main
