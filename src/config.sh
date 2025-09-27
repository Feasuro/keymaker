# Name of directory with iso files
BOOT_ISOS_DIR='boot-isos'

# Specify what to use as label for storage partition filesystem:
#   vendor - use device vendor name
#   model  - use device model name
#   none   - use string defined in STORAGE_LABEL
# when vendor/model is specified but not present STORAGE_LABEL is used as fallback
LABEL_USE_PROPERTY=vendor
# Filesystem label for storage partition.
# String up to 11 characters. (Truncated if too long!)
LABEL_STORAGE='Data'

# GPT partition names
STORAGE_PART_NAME='storage'
ESP_PART_NAME='esp'
SYSTEM_PART_NAME='system'

# Below variables define minimal sizes for partitions.
# Integer values are bytes, you can use IEC suffixes (Ki, Mi, Gi...).
MIN_STORAGE_SIZE=2Gi
MIN_ESP_SIZE=10Mi
MIN_SYSTEM_SIZE=5Gi
MIN_FREE_SIZE=1Gi

# Space at the beginning of a device reserved for bootloader.
# Default - first 1MiB. Integer value (in bytes) or IEC string.
# Don't change unless you're sure you know what you're doing!
PART_TABLE_OFFSET=1Mi

# Number of sectors reserved at the end of device
# for a backup of GPT partition table.
# Don't change unless you're sure you know what you're doing!
GPT_BACKUP_SECTORS=33
