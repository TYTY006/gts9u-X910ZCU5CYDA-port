#!/usr/bin/env bash
# restore-librepods.sh — re-apply the LibrePods Bluetooth-stack patch after a reboot.
#
# Prerequisites (once per boot):
#   1. Temporary root is active via KSuRoot / GhostLock:  /data/local/tmp/temp_su.sock exists
#      (run the x910_m.so payload from KSuRoot with Shizuku enabled)
#   2. USB debugging connected
#
# What it does:
#   - pushes su_client and the patched libbluetooth_jni.so if missing
#   - bind-mounts the patched library inside the zygote mount namespace
#   - restarts com.android.bluetooth so it picks the patched library up
#   - verifies the resulting md5
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-adb}"
DEV_SOCK=/data/local/tmp/temp_su.sock
DEV_CLIENT=/data/local/tmp/su_client
DEV_PATCH=/data/local/tmp/libbluetooth_patched.so
PATCH_LOCAL="$HERE/libbluetooth_patched.so"
CLIENT_LOCAL="$HERE/su_client"

say() { printf '\n=== %s ===\n' "$*"; }

say "checking device"
"$ADB" get-state >/dev/null

say "checking temporary root socket"
if ! "$ADB" shell "ls $DEV_SOCK" >/dev/null 2>&1; then
  echo "ERROR: $DEV_SOCK not found — start the temporary root payload first." >&2
  exit 1
fi

say "pushing helpers"
"$ADB" shell "ls $DEV_CLIENT" >/dev/null 2>&1 || "$ADB" push "$CLIENT_LOCAL" "$DEV_CLIENT"
"$ADB" shell "chmod 755 $DEV_CLIENT"
if ! "$ADB" shell "ls -l $DEV_PATCH" 2>/dev/null | grep -q "$(stat -c %s "$PATCH_LOCAL" 2>/dev/null || echo 0)"; then
  "$ADB" push "$PATCH_LOCAL" "$DEV_PATCH"
fi

say "root check"
"$ADB" shell "$DEV_CLIENT -c id"

say "bind-mounting patched library into zygote namespace"
"$ADB" shell "$DEV_CLIENT -c 'Z=\$(pidof zygote64); nsenter -t \$Z -m -- mount --bind $DEV_PATCH /apex/com.android.btservices/lib64/libbluetooth_jni.so; echo mount_rc=\$?'"

say "restarting bluetooth stack"
"$ADB" shell "$DEV_CLIENT -c 'kill -9 \$(pidof com.android.bluetooth) 2>/dev/null; sleep 4; echo new_pid=\$(pidof com.android.bluetooth)'"

say "verifying"
"$ADB" shell "$DEV_CLIENT -c 'NP=\$(pidof com.android.bluetooth); md5sum /proc/\$NP/root/apex/com.android.btservices/lib64/libbluetooth_jni.so'"
md5sum "$PATCH_LOCAL"

say "done — open LibrePods; the AirPods should connect and expose listening modes"
