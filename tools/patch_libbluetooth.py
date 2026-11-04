#!/usr/bin/env python3
"""Patch l2c_fcr_chk_chan_modes in a pulled libbluetooth_jni.so to return 1.

Equivalent to LibrePods' Xposed hook (l2c_fcr_hook.cpp) without any framework:
the L2CAP FCR channel-mode check is forced to succeed so AirPods can open the
AACP L2CAP channel.

Usage:
    pull the library first:
        adb pull /apex/com.android.btservices/lib64/libbluetooth_jni.so .

    then:
        python3 patch_libbluetooth.py libbluetooth_jni.so libbluetooth_patched.so

The offset below was derived for the SM-X910 / X910ZCU5CYDA build
(libbluetooth_jni.so, 13627064 bytes, md5 8a46139765d4c9109ce674ed9f3a0148).
On any other build, re-derive it: locate the "l2c_fcr_chk_chan_modes" string in
.rodata, find the code that references it, take the containing function's entry
and confirm the success path returns 1 before patching.
"""
import sys

# entry of l2c_fcr_chk_chan_modes (BTI at +0x...84, prologue at 0xaf0b88)
FUNC_OFF = 0xAF0B88
# mov w0, #1 ; ret
PATCH = bytes.fromhex("20008052c0035fd6")

EXPECTED_HEAD = bytes.fromhex("5e8600f83f2303d5")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 64
    src, dst = sys.argv[1], sys.argv[2]
    data = bytearray(open(src, "rb").read())
    if data[FUNC_OFF:FUNC_OFF + 8] != EXPECTED_HEAD:
        print(f"unexpected bytes at 0x{FUNC_OFF:x}: "
              f"{data[FUNC_OFF:FUNC_OFF + 8].hex()} — wrong library or offset")
        return 1
    data[FUNC_OFF:FUNC_OFF + 8] = PATCH
    open(dst, "wb").write(data)
    print(f"patched {src} -> {dst} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
