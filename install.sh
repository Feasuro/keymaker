#!/bin/bash

BACKTITLE="Keymaker"
DEBUG=1
GPT_BACKUP_SECTORS=33
PTABLE_OFFSET=1048576 # 1MiB in bytes

trap 'abort' INT
trap 'abort' TERM

abort() {
    echo "Application aborted." >&2
    exit 1
}

app_exit() {
    echo "Exiting." >&2
    exit 0
}

require_root() {
    # If we are already uid 0 (root) there is nothing to do
    [[ $(id -u) -eq 0 ]] && return 0

    # Prefer sudo
    if command -v sudo >/dev/null 2>&1; then
        echo "Requesting root privileges via sudo..." >&2
        exec sudo -E "$0" "$@"
    # Fallback to pkexec
    elif command -v pkexec >/dev/null 2>&1; then
        echo "Requesting root privileges via pkexec..." >&2
        exec pkexec "$0" "$@"
    else
        echo "Error: neither sudo nor pkexec is available. Cannot obtain root." >&2
        abort
    fi
}

handle_exit_code() {
    # Actions of dialog buttons
    case $1 in
        0) ((step++)) ;;
        1) app_exit ;;
        2) ;;
        3) ((step--)) ;;
        *) 
            echo "Error: Unknown exit code - ${1}" >&2
            abort
        ;;
    esac
}

find_devices() {
    # Find removable USB block devices and populate the associative array
    #   removable_devices[<devname>]="<vendor> <model>"
    #
    # Requirements (set in the caller):
    #   removable_devices[] – associative array
    #   DEBUG               – extra diagnostics
    echo "Looking for connected devices." >&2
    local sys_path id_bus id_vendor id_model devname label
    for sys_path in /sys/block/*; do
        # Reset variables for each iteration
        id_bus='' id_vendor='' id_model='' devname=''
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

        # Skip read-only devices
        if [[ -f "$sys_path/ro" && $(<"$sys_path/ro") -eq 1 ]]; then
            [ "$DEBUG" ] && echo "DEBUG find_devices: ${devname} is read-only, skipping." >&2
            continue
        fi

        # Sanitize: collapse whitespace in vendor/model string
        label="$(printf '%s %s' "$id_vendor" "$id_model" | tr -s '[:space:]' ' ')"
        # Only store safe device names (match /dev/sd[a-z]*)
        if [[ "$devname" =~ ^/dev/sd[a-z]+$ ]]; then
            removable_devices["$devname"]="$label"
        fi
    done
}

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

pick_device() {
    local result message ret dev
    local -a dialog_items

    device=''

    # Check if we have any devices
    if [[ ${#removable_devices[@]} -eq 0 ]]; then
        message="No removable USB devices found."
        echo "$message" >&2
    else
        message="Choose a removable USB device:"
        echo "Found devices:" "${!removable_devices[@]}" >&2
    fi

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
        --menu "$message" 15 60 6 \
        "${dialog_items[@]}"
        )

    ret=$?
    # Process selection
    if (( ret == 0 )); then
        case $result in
            other)
                manual_dev_entry ;;
            *)
                device="$result" ;;
        esac

        [[ -n $device ]] || ret=2
    fi

    echo "Chosen device: ${device}" >&2
    handle_exit_code $ret
}

pick_partitions() {
    local result ret opt
    local -a dialog_items

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
        --checklist "${message}Choose partitions to create:" 15 60 6 \
        "${dialog_items[@]}"
    )

    ret=$?
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
    fi

    handle_exit_code $ret
}

set_partition_vars() {
    # populate variables with device info and partitioning scheme
    local dev_size offset index

    if ! sector_size="$(blockdev --getss "${device}")"; then
        echo "ERROR: ${device} is inaccessible" >&2
        abort
    fi
    if ! dev_size="$(blockdev --getsz "${device}")"; then
        echo "ERROR: ${device} is inaccessible" >&2
        abort
    fi

    offset=$(( PTABLE_OFFSET / sector_size )) # first 1MiB (sectors)
    usable_size=$(( dev_size - offset - GPT_BACKUP_SECTORS )) # last sectors for gpt table backup
    # gpt partition names
    part_names=('storage' 'esp' 'system' 'free space')
    # define minimal partition sizes in bytes
    min_sizes=(2147483648 10485760 5368709120 1073741824) #2Gi 10Mi 5Gi 1Gi
    # convert min_sizes to sectors
    for index in "${!min_sizes[@]}"; do
        (( min_sizes[index] /= sector_size ))
    done

    # populate part_sizes with default weights (50MiB for part 2)
    calculate_sizes 2 $(( 52428800 / sector_size )) 2 1
}

calculate_sizes() {
    # calculate_sizes  <w0> <fixed_sz> <w2> <w3>
    #   $1 – weight for partition 0
    #   $2 – absolute size (in sectors) for partition 1 (fixed)
    #   $3 – weight for partition 2
    #   $4 – weight for partition 3
    #
    # Requirements (set in the caller):
    #   usable_size   – number of sectors available for partitions
    #   partitions[]  – flag array (0 = disabled, 1 = enabled) for each slot
    #   part_sizes[]  – array that will receive the calculated sizes
    local available ratio remainder index

    available=$(( usable_size - $2 ))
    ratio=$(( $1 * partitions[0] + $3 * partitions[2] + $4 * partitions[3] ))

    if (( ratio == 0 )); then
        [ "$DEBUG" ] && echo "DEBUG calculate_sizes: No partitions enabled (ratio = 0)." >&2
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
        if (( partitions[index] == 1 && index != 1 )); then
            (( part_sizes[index]++ ))
            (( remainder-- ))
        fi
        (( index = ++index % ${#partitions[@]} ))
    done

    if [ "$DEBUG" ]; then cat << EOF >&2
DEBUG calculate_sizes:
    available  = ${available} sectors
    ratio      = ${ratio}
    remainder  = ${remainder} sectors
    part_sizes = (${part_sizes[0]}, ${part_sizes[1]}, ${part_sizes[2]}, ${part_sizes[3]})
    sum(flex)  = $((part_sizes[0]+part_sizes[2]+part_sizes[3])) (should equal available)
EOF
    fi
}

validate_sizes() {
    # validate_sizes  <size1> <size2> <size3> <size4>
    #
    #   Arguments are user‑supplied sizes expressed as IEC strings
    #   (e.g. "2Gi", "500Mi", "1.5Ti").
    #
    # Requirements (set in the caller):
    #   sector_size   – sector size in bytes (e.g. 512)
    #   usable_size   – number of sectors available for partitions
    #   partitions[]  – flag array (0 = disabled, 1 = enabled)
    #   part_sizes[]  – current partition sizes (in sectors)
    #   part_names[]  – human‑readable names for the UI (optional)
    local sum index size
    local accepted=1
    local -a new_sizes
    message=''
    IFS=' '

    # assign new_sizes array with user input
    for index in "${!partitions[@]}"; do
        if (( partitions[index] == 0 )); then
            new_sizes+=(0)
            continue
        fi
        # check if iec strings match
        [ "$1" != "$(numfmt --to=iec-i $((part_sizes[index] * sector_size)))" ] && accepted=0

        new_sizes+=( $(( $(numfmt --from=iec-i "$1") / sector_size )) )
        shift
    done

    if [ "$DEBUG" ]; then cat << EOF >&2
DEBUG validate_sizes:
    part_sizes = ${part_sizes[*]}
    new_sizes  = ${new_sizes[*]}
    accepted   = ${accepted}
EOF
    fi

    # values were correct and accepted by user
    (( accepted == 1 )) && return 0

    # check if sizes are greater than minimum
    for index in "${!partitions[@]}"; do
        if (( partitions[index] == 1 && new_sizes[index] < min_sizes[index])); then
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
    if (( partitions[3] == 1 )); then
        if (( sum > usable_size && sum - new_sizes[3] < usable_size - min_sizes[3] )); then
            [ "$DEBUG" ] && echo "   adjust free space down" >&2
            (( new_sizes[3] -= sum - usable_size ))
            sum=$usable_size
        elif (( sum < usable_size )); then
            [ "$DEBUG" ] && echo "   adjust free space up" >&2
            (( new_sizes[3] += usable_size - sum ))
            sum=$usable_size
        fi
    fi

    # if partitions don't fit recalculate sizes proportionally
    if (( sum != usable_size )); then
        message+="\Z1Partitions scaled to fit disk size!\Zn\n"
        # shellcheck disable=SC2068
        calculate_sizes ${new_sizes[@]}
        return 2
    fi

    # new sizes are correct
    message+="\Z2Press next to accept changes.\Zn\n"
    part_sizes=("${new_sizes[@]}")
    return 2
}

set_partitions_size() {
    local result count size ret index
    local -a dialog_items

    # Build dialog items
    dialog_items=()
    count=0
    for index in "${!partitions[@]}"; do
        if (( partitions[index] == 1 )); then
            ((count++))
            size=$(numfmt --to=iec-i $((part_sizes[index] * sector_size)))
            dialog_items+=("${device}${count} ${part_names[$index]}" \
                "$count" 1 "$size" "$count" 30 15 0)
        fi
    done
    # Remove /dev/sdxN before free space
    ((partitions[3] == 1 )) && dialog_items[-8]="${part_names[3]}"

    # Show dialog
    result=$(dialog --keep-tite --extra-button --colors --stdout \
        --backtitle "$BACKTITLE" \
        --title "Adjust partition sizes" \
        --ok-label "Next" \
        --cancel-label "Exit" \
        --extra-label "Back" \
        --form "${message}The following partitions will be created:" \
        20 60 4 "${dialog_items[@]}"
    )

    ret=$?
    # Process input
    if (( ret == 0 )); then
        # shellcheck disable=SC2086
        IFS=$'\n' validate_sizes $result
        (( ret += $? ))
    fi

    handle_exit_code $ret
}

main() {
    require_root "$@"

    local step=1
    local -A removable_devices
    local message device sector_size usable_size 
    local -a partitions part_sizes part_names min_sizes

    message=''

    while true; do
        case $step in
            1)
                find_devices
                pick_device
                ;;
            2)
                pick_partitions
                set_partition_vars
                ;;
            3)
                set_partitions_size
                ;;
            4)
                echo "Finished." >&2
                break
                ;;
        esac
    done
}

main "$@"
