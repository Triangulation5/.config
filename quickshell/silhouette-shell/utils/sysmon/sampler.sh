#!/bin/sh
# POSIX shell fallback sampler for Sysmon.qml.
# Emits hardware detection and live system vitals over stdout.

ONCE=0
VITALS_ONLY=0
DETECT_ONLY=0
WATCH_PID=""
INTERVAL_MS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --once) ONCE=1; shift ;;
        --vitals-only) VITALS_ONLY=1; shift ;;
        --detect-only) DETECT_ONLY=1; shift ;;
        --watch-pid) WATCH_PID="$2"; shift 2 ;;
        --interval) INTERVAL_MS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ "$ONCE" -eq 1 ]; then
    read -r _ a b c d e f g h _ < /proc/stat 2>/dev/null
    echo "CPU $((a+b+c+d+e+f+g+h)) $((d+e))"
    awk '/^MemTotal:/{mt=$2}/^MemAvailable:/{ma=$2}END{print "MEM",mt+0,ma+0}' /proc/meminfo 2>/dev/null
    exit 0
fi

if [ -n "$WATCH_PID" ]; then
    page=$(getconf PAGESIZE 2>/dev/null || echo 4096)
    sec=$(( (${INTERVAL_MS:-8000} + 500) / 1000 ))
    [ "$sec" -lt 1 ] && sec=1
    while [ -r "/proc/$WATCH_PID/statm" ]; do
        read -r _ r _ < "/proc/$WATCH_PID/statm" 2>/dev/null || break
        echo "RSS $((r * page / 1024 / 1024))"
        sleep "$sec"
    done
    exit 0
fi

if [ "$VITALS_ONLY" -eq 1 ]; then
    sec=$(( (${INTERVAL_MS:-2000} + 500) / 1000 ))
    [ "$sec" -lt 1 ] && sec=1
    while true; do
        read -r _ a b c d e f g h _ < /proc/stat 2>/dev/null
        echo "CPU $((a+b+c+d+e+f+g+h)) $((d+e))"
        awk '/^MemTotal:/{mt=$2}/^MemAvailable:/{ma=$2}END{print "MEM",mt+0,ma+0}' /proc/meminfo 2>/dev/null
        sleep "$sec"
    done
fi

detect_temp() {
    tp=""
    for h in /sys/class/hwmon/hwmon*; do
        [ -d "$h" ] || continue
        for l in "$h"/temp*_label; do
            [ -r "$l" ] || continue
            if [ "$(cat "$l" 2>/dev/null)" = "Tdie" ]; then
                tp="${l%_label}_input"
                break 2
            fi
        done
    done
    if [ -z "$tp" ]; then
        for h in /sys/class/hwmon/hwmon*; do
            [ -d "$h" ] || continue
            for l in "$h"/temp*_label; do
                [ -r "$l" ] || continue
                if [ "$(cat "$l" 2>/dev/null)" = "Package id 0" ]; then
                    tp="${l%_label}_input"
                    break 2
                fi
            done
        done
    fi
    if [ -z "$tp" ]; then
        for h in /sys/class/hwmon/hwmon*; do
            [ -d "$h" ] || continue
            for l in "$h"/temp*_label; do
                [ -r "$l" ] || continue
                if [ "$(cat "$l" 2>/dev/null)" = "Tctl" ]; then
                    tp="${l%_label}_input"
                    break 2
                fi
            done
        done
    fi
    if [ -z "$tp" ]; then
        for h in /sys/class/hwmon/hwmon*; do
            if [ -r "$h/temp1_input" ]; then
                tp="$h/temp1_input"
                break
            fi
        done
    fi
    if [ -n "$tp" ]; then
        echo "DETECT TEMP $tp"
    else
        echo "DETECT TEMP -"
    fi
}

detect_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        echo "DETECT GPU nvidia"
        GPU_VENDOR="nvidia"
    else
        GPU_VENDOR="none"
        for d in /sys/class/drm/card*/device; do
            [ -r "$d/vendor" ] || continue
            if [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1002" ] && [ -r "$d/gpu_busy_percent" ]; then
                v=0
                [ -r "$d/mem_info_vram_total" ] && v=1
                echo "DETECT GPU amd $d $v"
                GPU_VENDOR="amd"
                AMD_DEV="$d"
                break
            fi
        done
        if [ "$GPU_VENDOR" = "none" ]; then
            echo "DETECT GPU none"
        fi
    fi
}

detect_temp
detect_gpu

if [ "$DETECT_ONLY" -eq 1 ]; then
    exit 0
fi

tick=0
while true; do
    # Fast metrics (1s)
    read -r _ a b c d e f g h _ < /proc/stat 2>/dev/null
    echo "CPU $((a+b+c+d+e+f+g+h)) $((d+e))"

    awk '/^MemTotal:/{mt=$2}/^MemAvailable:/{ma=$2}/^SwapTotal:/{st=$2}/^SwapFree:/{sf=$2}END{print "MEM",mt+0,ma+0,st+0,sf+0}' /proc/meminfo 2>/dev/null
    awk 'NR>2{gsub(":"," ");if($1!="lo"){rx+=$2;tx+=$10}}END{print "NET",rx+0,tx+0}' /proc/net/dev 2>/dev/null

    if [ -n "$tp" ] && [ -r "$tp" ]; then
        echo "TMP $(cat "$tp" 2>/dev/null)"
    else
        echo "TMP -"
    fi

    # GPU metrics (2s)
    if [ $((tick % 2)) -eq 0 ]; then
        if [ "$GPU_VENDOR" = "nvidia" ]; then
            line=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1)
            [ -n "$line" ] && echo "GPU_NV $line"
        elif [ "$GPU_VENDOR" = "amd" ] && [ -n "$AMD_DEV" ]; then
            busy=$(cat "$AMD_DEV/gpu_busy_percent" 2>/dev/null)
            temp=$(cat "$AMD_DEV"/hwmon/hwmon*/temp1_input 2>/dev/null | head -n1)
            vu=$(cat "$AMD_DEV/mem_info_vram_used" 2>/dev/null)
            vt=$(cat "$AMD_DEV/mem_info_vram_total" 2>/dev/null)
            echo "GPU_AMD ${busy:-0} ${temp:-0} ${vu:-0} ${vt:-0}"
        fi
    fi

    # Slow metrics (5s, plus tick 0)
    if [ $((tick % 5)) -eq 0 ]; then
        df -P / 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i~/%$/){gsub("%","",$i);print "DISK "$i}}'
        awk '{print "UP "int($1)}' /proc/uptime 2>/dev/null
    fi

    tick=$((tick + 1))
    sleep 1
done
