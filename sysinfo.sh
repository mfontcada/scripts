#!/usr/bin/env bash
# Combined system metrics

# ---------- CPU USAGE (lightweight, /proc/stat) ----------
cpu_usage() {
  read -r cpu u n s id io irq sirq st _ </proc/stat
  idle0=$((id + io))
  total0=$((u + n + s + id + io + irq + sirq + st))
  sleep 0.5
  read -r cpu u n s id io irq sirq st _ </proc/stat
  idle1=$((id + io))
  total1=$((u + n + s + id + io + irq + sirq + st))
  didle=$((idle1 - idle0))
  dtotal=$((total1 - total0))
  awk -v dI="$didle" -v dT="$dtotal" 'BEGIN { printf "%.0f", (1 - dI/dT) * 100 }'
}

# ---------- CPU TEMP (try sensors, then hwmon/sysfs) ----------
cpu_temp() {
  if command -v sensors >/dev/null 2>&1; then
    # Try common labels first
    t=$(sensors 2>/dev/null | awk '/^(Package id 0|Tctl|Tdie|CPU Temperature):/ {print $2; exit}')
    if [[ -n "$t" ]]; then
      echo "${t//[+°C]/}"
      return
    fi
  fi
  # Fallback: try thermal zones
  for z in /sys/class/thermal/thermal_zone*; do
    [[ -r "$z/type" && -r "$z/temp" ]] || continue
    tp=$(cat "$z/type")
    case "$tp" in
    x86_pkg_temp | cpu-thermal | acpitz | soc_thermal)
      printf "%.0f\n" "$(awk '{print $1/1000}' "$z/temp")"
      return
      ;;
    esac
  done
  echo "--"
}

# ---------- GPU (detect vendor, then usage/temp) ----------
gpu_info() {
  local usage="--" temp="--"

  # Prefer first DRM device
  for dev in /sys/class/drm/card*/device; do
    [[ -r "$dev/vendor" ]] || continue
    ven=$(cat "$dev/vendor")
    case "$ven" in
    0x10de) # NVIDIA
      if command -v nvidia-smi >/dev/null 2>&1; then
        # Query first GPU
        line=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)
        usage=${line%%,*}
        temp=${line##*, }
      fi
      echo "$usage|$temp"
      return
      ;;
    0x1002 | 0x1022) # AMD
      # Usage from amdgpu sysfs if available
      if [[ -r "$dev/gpu_busy_percent" ]]; then
        usage=$(cat "$dev/gpu_busy_percent" 2>/dev/null)
      fi
      # Temp via hwmon
      if [[ -d "$dev/hwmon" ]]; then
        for h in "$dev"/hwmon/hwmon*/temp*_input; do
          [[ -r "$h" ]] || continue
          temp=$(awk '{printf "%.0f",$1/1000}' "$h")
          break
        done
      fi
      echo "$usage|$temp"
      return
      ;;
    0x8086) # Intel
      # Temp via hwmon if present
      if [[ -d "$dev/hwmon" ]]; then
        for h in "$dev"/hwmon/hwmon*/temp*_input; do
          [[ -r "$h" ]] || continue
          temp=$(awk '{printf "%.0f",$1/1000}' "$h")
          break
        done
      fi
      # Usage (optional): needs intel_gpu_top; we try a quick sample
      if command -v intel_gpu_top >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        # Grab a single JSON sample (200ms) and average engine "busy"
        sample=$(timeout 0.3s intel_gpu_top -J -s 200 2>/dev/null | head -n 200)
        if [[ -n "$sample" ]]; then
          # sum "busy" values and average over count
          usage=$(awk -v RS=',' 'match($0,/"busy" *: *([0-9.]+)/,m){s+=m[1]; c++} END{if(c) printf("%.0f", s/c)}' <<<"$sample")
          [[ -z "$usage" ]] && usage="--"
        fi
      fi
      echo "$usage|$temp"
      return
      ;;
    esac
  done

  # Fallback (no DRM device found)
  echo "$usage|$temp"
}

# ---------- RAM (from /proc/meminfo, human-readable) ----------
ram_usage() {
  awk '
    /^MemTotal:/ {t=$2}
    /^MemAvailable:/ {a=$2}
    END {
      u=t-a
      # Convert to human-readable GB with 1 decimal
      printf "%.1f/%.0fG", u/1024/1024, t/1024/1024
    }' /proc/meminfo
}

# ----- DISK USAGE -----
DISK_MOUNT="/"
disk_usage() {
  read -r size used _ <<<"$(df -BG --output=size,used "$DISK_MOUNT" | tail -n 1)"
  echo "${used}/${size}"
}

# Collect
CPU_PCT=$(cpu_usage)
CPU_TMP=$(cpu_temp)

IFS='|' read -r GPU_PCT GPU_TMP <<<"$(gpu_info)"
[[ -z "$GPU_PCT" ]] && GPU_PCT="--"
[[ -z "$GPU_TMP" ]] && GPU_TMP="--"

RAM_STR=$(ram_usage)
DISK_STR=$(disk_usage)

echo "CPU: ${CPU_PCT}% ${CPU_TMP}°C | GPU: ${GPU_PCT}% ${GPU_TMP}°C | RAM: ${RAM_STR} | Disk: ${DISK_STR}"
