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
#   SHARED_DIR    – absolute path to the shared directory.
#   device        – full block‑device path (e.g. /dev/sdb)
#   part_nodes[]  – array with partition nodes
# Return codes:
#   0        – GRUB was installed successfully on both targets.
#   non-zero – Any step failed.
# -------------------------------------------------
install_bootloader() {
   local efi_dir sys_dir grub_dir grub_env

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

   grub_dir="${SHARED_DIR}/grub"
   grub_env="${sys_dir}/grub/grubenv"

   log i "Commencing GRUB installation."
   grub-install --target=i386-pc --force --boot-directory="$sys_dir" "$device"
   grub-install --target=x86_64-efi --removable --boot-directory="$sys_dir" --efi-directory="$efi_dir"
   install -d "${sys_dir}/${BOOT_ISOS_DIR}"
   install -Dm0644 -t "${sys_dir}/grub/" "${grub_dir}/"*.cfg
   install -Dm0644 -t "${sys_dir}/grub/themes/" "${grub_dir}/themes/background.png"

   # Setup GRUB environment variables
   grub-editenv "${grub_env}" set pager=1
   grub-editenv "${grub_env}" set sys_uuid="$(lsblk -ln -o UUID "${part_nodes[2]}")"
   grub-editenv "${grub_env}" set iso_dir="/${BOOT_ISOS_DIR}"
   grub-editenv "${grub_env}" set locale_dir=/grub/locale
   grub-editenv "${grub_env}" set lang="${LANG::2}"
   grub-editenv "${grub_env}" set gfxmode=auto
   grub-editenv "${grub_env}" set gfxterm_font=unicode
   grub-editenv "${grub_env}" set color_normal=green/black
   grub-editenv "${grub_env}" set color_highlight=black/light-green
   grub-editenv "${grub_env}" set timeout_style=menu
   grub-editenv "${grub_env}" set timeout=10
   grub-editenv "${grub_env}" set default=0
}
