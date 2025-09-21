#!/bin/bash

# Space at the beginning of a device reserved for bootloader.
# First 1MiB (in bytes).
# Don't change unless you're sure you know what you're doing!
PART_TABLE_OFFSET=1048576

# Number of sectors reserved at the end of device
# for a backup of GPT partition table.
# Don't change unless you're sure you know what you're doing!
GPT_BACKUP_SECTORS=33
