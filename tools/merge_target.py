#!/usr/bin/env python3
"""以真机验证过的 X910 profile 为骨架，叠加本机推导的地址常量。"""
import re
import shutil
from pathlib import Path

base_dir = Path('/mnt/d/AI_use_huaweishouji/samroot/rmgp_pr/src/targets')
ours_dir = base_dir / 'gts9u-X910ZCU5CYDA'
ref_dir = base_dir / 'gts9uwifi-X910XXS6EZH3'
out_dir = base_dir / 'gts9u-X910ZCU5CYDA-merged'
out_dir.mkdir(exist_ok=True)


def parse(path):
    vals = {}
    for ln in path.read_text(encoding='utf-8').splitlines():
        m = re.match(r'^#define\s+([A-Za-z0-9_]+)\s+(\S.*)$', ln)
        if m and not m.group(2).strip().endswith('\\'):
            vals[m.group(1)] = m.group(2).strip()
    return vals


ours = parse(ours_dir / 'target.h')
ref = parse(ref_dir / 'target.h')

# 这些属于"引擎策略"，一律保留参考 profile 的值
keep_ref = {
    'SLIDE_MCAST_DOMAIN', 'SLIDE_MCAST_LEVEL', 'SLIDE_MCAST_OPTION',
    'SLIDE_MAX_ATTEMPTS', 'SLIDE_P0_OFFSET_CANDIDATES',
    'APPENDED_FUTEXES', 'MM_ORDER', 'KMALLOC_CGROUP_TYPE', 'KMALLOC_CACHE_TYPES',
    'AVERAGE', 'REPEAT_MEASUREMENT', 'PIPE_MAX_ATTEMPTS', 'ROUTE_WAIT_SECONDS',
}

out_lines = []
changed = []
for ln in (ref_dir / 'target.h').read_text(encoding='utf-8').splitlines():
    m = re.match(r'^#define\s+([A-Za-z0-9_]+)\s+(\S.*)$', ln)
    if m:
        key = m.group(1)
        if key in ours and key not in keep_ref and not ours[key].endswith('\\'):
            if ours[key] != m.group(2).strip():
                out_lines.append(f'#define {key} {ours[key]}')
                changed.append((key, m.group(2).strip(), ours[key]))
                continue
    out_lines.append(ln)

# 补上参考里没有、但我们推导出的地址类常量
for key in ('SLIDE_KASLR_STEP', 'SLIDE_TRACEFS_VFORK_CALLER_OFF', 'SLIDE_PSELECT_NFDS'):
    if key in ours and key not in ref:
        out_lines.append(f'#define {key} {ours[key]}')
        changed.append((key, '(absent)', ours[key]))

(out_dir / 'target.h').write_text('\n'.join(out_lines) + '\n', encoding='utf-8')
shutil.copy(ours_dir / 'p0_fingerprint.h', out_dir / 'p0_fingerprint.h')

print(f'overlaid {len(changed)} values')
for k, a, b in changed[:40]:
    print(f'  {k:<38} ref->{a[:20]:<22} ours->{b[:20]}')
