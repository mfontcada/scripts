#!/usr/bin/env bash
# Show screen brightness percentage

# Try to auto-detect backlight device
dev=$(ls /sys/class/backlight | head -n 1)
[[ -z "$dev" ]] && {
  echo "--%"

  exit
}

max=$(cat /sys/class/backlight/$dev/max_brightness)
cur=$(cat /sys/class/backlight/$dev/brightness)
pct=$((cur * 100 / max))

echo "${pct}%"
