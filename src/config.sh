# Name of directory with iso files
BOOT_ISOS_DIR='boot-isos'

# GPT partition names
STORAGE_PART_NAME='storage'
ESP_PART_NAME='esp'
SYSTEM_PART_NAME='system'

# Below variables define minimal sizes for partitions (in bytes).
MIN_STORAGE_SIZE=2147483648 # 2GiB
MIN_ESP_SIZE=10485760       # 10MiB
MIN_SYSTEM_SIZE=5368709120  # 5GiB
MIN_FREE_SIZE=1073741824    # 1GiB

# Space at the beginning of a device reserved for bootloader.
# First 1MiB (in bytes).
# Don't change unless you're sure you know what you're doing!
PART_TABLE_OFFSET=1048576

# Number of sectors reserved at the end of device
# for a backup of GPT partition table.
# Don't change unless you're sure you know what you're doing!
GPT_BACKUP_SECTORS=33
