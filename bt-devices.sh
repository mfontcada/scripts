#!/usr/bin/env bash
# Count connected Bluetooth devices and output as "N device(s)"

count=$(bluetoothctl info | grep -c "Connected: yes")

if [ "$count" -eq 1 ]; then
  echo "1 device"
else
  echo "${count} devices"
fi
