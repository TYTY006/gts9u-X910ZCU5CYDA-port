# Galaxy Tab S9 Ultra SM-X910 / X910ZCU5CYDA port record (kernel 5.15.153)

Status: **temporary root achieved and verified on real hardware**; bootloader stayed
locked and Knox was not tripped throughout.

This record documents a fourth data point for the `gts9u` board: the *older* China
build `X910ZCU5CYDA` (kernel 5.15.153), as opposed to the device-tested
`X916BXXS6EZG3` / `X910XXS6EZH3` builds (kernel 5.15.189) already covered upstream.

## Device identity

```text
model: SM-X910
device: gts9uwifi
region/CSC: CHN
AP/PDA build: X910ZCU5CYDA
display build: AP3A.240905.015.A2.X910ZCU5CYDA
fingerprint: samsung/gts9uwifizc/gts9uwifi:15/AP3A.240905.015.A2/X910ZCU5CYDA:user/release-keys
security patch level: 2025-03-01
kernel release: 5.15.153-android13-8-2370170-abX910ZCU5CYDA
kernel build: #1 SMP PREEMPT Mon Apr 21 01:36:15 UTC 2025, clang LTO
Android version: 15
page size: 4096
SoC: Qualcomm SM8550 (Kalama), 12 GB
bootloader/verified boot: locked, green (stock, unmodified throughout)
Knox warranty bit: 0 (never tripped)
```

## Why a separate profile is required

Payloads are matched on the **full kernel release string**. `5.15.153` and
`5.15.189` are different builds with different symbol addresses; the upstream
`gts9uwifi-X910XXS6EZH3` profile therefore cannot be reused as-is.

## How the profile was produced

### 1. Extract and derive

`tools/generate_target.py` (from HyperRamzey's tree, as referenced in PR #343) run
against the stock `boot.img` from the official `X910ZCU5CYDA` firmware:

```bash
python3 tools/generate_target.py \
  --boot boot.img \
  --phys-offset 0x80000000 \
  --kernel-phys 0x80000000 \
  --profile gts9u-X910ZCU5CYDA \
  --model SM-X910 \
  --fingerprint "samsung/gts9uwifizc/gts9uwifi:15/AP3A.240905.015.A2/X910ZCU5CYDA:user/release-keys" \
  --out src/targets/gts9u-X910ZCU5CYDA
```

Derived values (all from this device's own Image):

```text
KIMAGE_TEXT_BASE      0xffffffc008000000
P0_PHYS_OFFSET        0x80000000
P0_KERNEL_PHYS_LOAD   0x80000000
SLIDE_TRACEFS_EVENT_ID            108
SLIDE_TRACEFS_WORKER_CALLER_OFF   0x0010d370
MM_STRUCT_SZ                      0x400
MCAST_WAITER_OFF                  0x78
p0 fingerprint                    125 rows, probe 0x1f0000, 16K slide step
```

Two corrections were needed relative to a naive run:

* **`--kernel-phys` must be `0x80000000`, not the UEFI `"Kernel"` region
  (`0xa8000000`).** The UEFI entry is the bootloader staging area; the Image runs
  from the DRAM base. Using `0xa8000000` makes every derived alias point at the
  wrong physical page and the exploit panics in the mm-group stage.
* **`generate_target.py`'s `worker_caller_off()` regex only matches GNU objdump
  byte formatting**, so it aborts with `no 'bl schedule' in worker_thread
  disassembly` on llvm-objdump ≥ 14 (which prints `d7 e6 54 94` instead of
  `d7e65494`). See `patches/generate_target-llvm-objdump.patch`.

### 2. Merge the engine configuration

`generate_target.py` derives addresses only; the engine policy block
(`APP_*`, `KERNELSNITCH_*`, `MM_*_ALIAS_*`, `S918_*`, `PIPE_*`, …) is not emitted.
The target therefore has to be layered onto an existing, device-tested profile:

```bash
python3 tools/merge_target.py   # takes gts9uwifi-X910XXS6EZH3 as the skeleton
```

Rules used:

* skeleton = `gts9uwifi-X910XXS6EZH3/target.h` (same board, complete engine config);
* overlay = every address-like `#define` derived for this build (all `*_OFF`,
  `KIMAGE_TEXT_BASE`, `P0_*`, `SLIDE_*` offsets, `BUILD_*`, `P0_ORACLE_*`);
* keep from the skeleton: `SLIDE_MCAST_*`, `SLIDE_MAX_ATTEMPTS`,
  `SLIDE_P0_OFFSET_CANDIDATES`, `APPENDED_FUTEXES`, `MM_ORDER`,
  `KMALLOC_*`, `PIPE_MAX_ATTEMPTS`, `ROUTE_WAIT_SECONDS`;
* fingerprint header = the one generated for this device (never the skeleton's).

31 values end up replaced; all of them are addresses.

### 3. Build

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
make TARGET=gts9u-X910ZCU5CYDA-merged
# -> build/gts9u-X910ZCU5CYDA-merged/cve-2026-43499-app.so  (137 KB)
```

Add to the `Makefile`:

```make
ifeq ($(TARGET),gts9u-X910ZCU5CYDA-merged)
APP_TARGET_CFLAGS := -DSLIDE_STACK_WRITER=1
endif
```

The `${P0_KERNEL_PHYS_LOAD}` in this target is `0x80000000`.

## Running it

**Shizuku is mandatory on this device.** The tracefs KASLR slide reads
`/sys/kernel/tracing/tracing_on`, which `untrusted_app` cannot open
(`errno=13`, EACCES). Shell belongs to `readtracefs` and can read it, so the
payload must be launched through Shizuku (KSuRoot's "使用 Shizuku" switch, or
`ghostlock --load-prebuilt-profile` from a shell context).

Without Shizuku every attempt fails identically:

```text
[-] slide tracefs open read failed path=/sys/kernel/tracing/tracing_on errno=13
[-] exploit attempt=24/24 failed status=255
```

With it:

```text
[+] slide-kaslr-ok source=tracefs pid=... base=ffffffc008140000 slide=0000000000140000
[+] controlled mm group search scans=256 objects=32 dma32_skip=8
[+] 已获取 bootstrap root
[+] KernelSU 已启用
```

## Verification

```text
$ adb shell getenforce
Permissive                     # kernel variable rewritten by the exploit
$ adb shell ps -A -o NAME | grep ksu
ksu-helper
ksu-helper
$ getprop ro.boot.warranty_bit
0                              # Knox intact
$ getprop ro.boot.flash.locked
1                              # bootloader still locked
```

KernelSU manager reports the running kernel as
`5.15.153-android13-8-2370170-abX910ZCU5CYDA` and SELinux as permissive.

## Limits

* **Temporary root.** KernelSU is injected at runtime; a full reboot clears it.
  `su` is only visible to apps granted by the KernelSU manager — `adb shell`
  (uid 2000) cannot use it, and `/data/adb` is mode 0700 root.
* **No Zygisk / LSPosed.** Zygisk has to hook zygote at start, so a framework
  cannot be installed on top of an at-runtime root. This turned out **not** to be a
  blocker for root-level work: see "Root shell and LibrePods without Xposed" below.
  `/data/adb` is mode 0700 root, so `adb shell` still cannot use `su` directly.
* Android 15 / One UI 7 only; not tested against `X910XXS6EZH3` (5.15.189), which
  already has its own profile.

## Root shell and LibrePods without Xposed

The payload leaves a su daemon on `/data/local/tmp/temp_su.sock` whose
`allowed_client_uid` is **2000 (shell)**, so a small client is enough to get a
kernel-domain root shell over adb — no manager approval needed:

```text
$ adb push su_client /data/local/tmp/ && adb shell chmod 755 /data/local/tmp/su_client
$ adb shell /data/local/tmp/su_client -c id
uid=0(root) gid=0(root) groups=0(root) context=u:r:kernel:s0
```

Wire format (see `src/su_daemon.c` upstream): one byte `F` plus 5 file
descriptors via `SCM_RIGHTS` (stdin, stdout, stderr, cwd, io), then
`struct su_request_header` (magic `0x53553235`, version 1), then `argc` argv
strings and `envc` envp strings, each as `u32 length + bytes`. The daemon
overwrites `argv[0]` with `sh`, so the first argument you pass is `sh`'s first
argument (`-c`).

That makes Xposed unnecessary for the main LibrePods use case. LibrePods needs
Xposed only to run two native hooks:

```c
uint8_t l2c_fcr_chk_chan_modes(void *) { return 1; }        /* L2CAP mode check */
BTA_DmSetLocalDiRecord(...) { vendor = 0x004C; ... }        /* Apple vendor id  */
```

`l2c_fcr_chk_chan_modes` lives in
`/apex/com.android.btservices/lib64/libbluetooth_jni.so`. The library is stripped,
so the function was located through its own `__func__` string in `.rodata`
(file offset `0x84cd8`): the code that references it starts at `0xaf0b88`, and it
returns 0 on the failure path / 1 on success. Patching the entry to
`mov w0,#1; ret` reproduces the hook exactly:

```text
original: 5e8600f8 3f2303d5      (PAC prologue)
patched:  20008052 c0035fd6      (mov w0,#1 ; ret)
```

The library sits on a read-only APEX and `/apex` is mounted per-process, so the
patch is applied by bind-mounting the patched file **inside the zygote mount
namespace**, which every freshly forked process inherits:

```sh
PATCH=/data/local/tmp/libbluetooth_patched.so
Z=$(pidof zygote64)
nsenter -t $Z -m -- mount --bind $PATCH \
  /apex/com.android.btservices/lib64/libbluetooth_jni.so
kill -9 $(pidof com.android.bluetooth)
```

`restore-librepods.sh` does all of the above (root check, push, bind mount,
bluetooth restart, md5 verification) and is the one command to run after each
reboot, once the payload is running.

Verified end to end on the device: LibrePods reads battery/ear state and switches
listening modes; the AACP round trip is visible in logcat.

```text
Sending packet: 04 00 04 00 09 00 0D 03 00 00 00
Control command: 0d - 03
Control command received: 0d - 03
calling listener for LISTENING_MODE
```

Known limitation: **Off (0x0d-01) is refused by the earbuds** — they answer
`0x0d-04` (Adaptive) and emit an unhandled `0x52` packet, because the firmware
drops the Off slot while Adaptive Audio is enabled (same as iOS). Transparency,
ANC and Adaptive all work.

## Files

```text
target/target.h              merged target (engine config + this build's addresses)
target/p0_fingerprint.h      fingerprint generated from this build's Image
tools/merge_target.py        skeleton/overlay merge used above
tools/patch_libbluetooth.py  patches l2c_fcr_chk_chan_modes to return 1
su_client.c                  root-shell client for /data/local/tmp/temp_su.sock
restore-librepods.sh         one-shot: root check + bind mount + bluetooth restart
patches/generate_target-llvm-objdump.patch
```

## Credits

* `BuSung-dev` for Root My Galaxy and the payload engine.
* `goisneto` for PR #343 (`gts9uwifi-X910XXS6EZH3`), which supplied the engine
  configuration this profile is layered on.
* `HyperRamzey` for `generate_target.py`.
* `YuKongA` for GhostLock, whose extractor independently confirmed the KASLR
  layout and the `remove_waiter` primitive on this build.
