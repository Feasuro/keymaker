#!/bin/bash
# boot_utils.sh
# Depends on: common.sh
# Usage: source boot_utils.sh and deps, in any order.
[[ -n "${BOOT_UTILS_SH_INCLUDED:-}" ]] && return
BOOT_UTILS_SH_INCLUDED=1

# -------------------------------------------------
# Usage: install_bootloader
# Purpose: Installs GRUB on the target device for both legacy BIOS
#          and UEFI platforms.
# Parameters: none – function relies on runtime variables
# Variables used/set:
#   device        – full block‑device path (e.g. /dev/sdb)
#   part_nodes[]  – array with partition nodes
# Return codes:
#   0        – GRUB was installed successfully on both targets.
#   non-zero – Any step failed.
# -------------------------------------------------
install_bootloader() {
   local efi_dir sys_dir
   # default mountpoints
   efi_dir='/tmp/esp'
   sys_dir='/tmp/system'
   # real mountpoints
   efi_dir=$(findmnt -ln -o TARGET "${part_nodes[1]}" 2>/dev/null || {
      mkdir -p "$efi_dir" &&
      mount "${part_nodes[1]}" "$efi_dir" &&
      echo "$efi_dir"
   })
   sys_dir=$(findmnt -ln -o TARGET "${part_nodes[2]}" 2>/dev/null || {
      mkdir -p "$sys_dir" &&
      mount "${part_nodes[2]}" "$sys_dir" &&
      echo "$sys_dir"
   })

   log i "Commencing GRUB installation."
   grub-install --target=i386-pc --force --boot-directory="$sys_dir" "$device"
   grub-install --target=x86_64-efi --removable --boot-directory="$sys_dir" --efi-directory="$efi_dir"
}
