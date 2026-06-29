#!/usr/bin/env python3
"""Parse strace output and generate a minimal OCI seccomp profile."""

import argparse
import json
import re
import sys
from collections import Counter

SYSCALL_RE = re.compile(r'^(?:\[pid\s+\d+\]\s+)?(\w+)\(')

MANDATORY_BASELINE = {
    'execve', 'brk', 'mmap', 'mprotect', 'munmap',
    'arch_prctl', 'set_tid_address', 'set_robust_list',
    'read', 'write', 'close', 'fstat', 'newfstatat',
    'openat', 'access', 'faccessat2',
    'rt_sigaction', 'rt_sigprocmask', 'rt_sigreturn',
    'clone', 'clone3', 'wait4', 'exit_group', 'exit',
    'getpid', 'getppid', 'gettid', 'getuid', 'getgid',
    'geteuid', 'getegid',
    'futex', 'nanosleep', 'clock_nanosleep',
    'pipe2', 'dup', 'dup2', 'dup3', 'fcntl',
    'ioctl', 'lseek',
    'getrandom', 'prlimit64',
    'sigaltstack', 'sched_getaffinity',
    'rseq',
}

ALWAYS_BLOCKED = {
    'kexec_load', 'kexec_file_load', 'reboot',
}

DANGEROUS_SYSCALLS = {
    'ptrace', 'process_vm_readv', 'process_vm_writev',
    'mount', 'umount', 'umount2', 'unshare',
    'keyctl', 'bpf', 'perf_event_open',
    'init_module', 'finit_module', 'delete_module',
    'pivot_root', 'userfaultfd',
}


def parse_strace_log(path):
    counts = Counter()
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('---') or line.startswith('+++'):
                continue
            m = SYSCALL_RE.match(line)
            if m:
                counts[m.group(1)] += 1
    return counts


def generate_profile(observed):
    allowed = (set(observed.keys()) | MANDATORY_BASELINE) - ALWAYS_BLOCKED

    profile = {
        "defaultAction": "SCMP_ACT_ERRNO",
        "syscalls": [
            {
                "names": sorted(allowed),
                "action": "SCMP_ACT_ALLOW"
            },
            {
                "names": sorted(ALWAYS_BLOCKED),
                "action": "SCMP_ACT_ERRNO",
                "errnoRet": 1
            }
        ]
    }
    return profile


def print_summary(observed):
    print(f"\n{'='*60}")
    print(f"Seccomp Profile Generation Summary")
    print(f"{'='*60}")
    print(f"Unique syscalls observed: {len(observed)}")
    print(f"Baseline syscalls added:  {len(MANDATORY_BASELINE - set(observed.keys()))}")
    print(f"Total allowed syscalls:   {len((set(observed.keys()) | MANDATORY_BASELINE) - ALWAYS_BLOCKED)}")
    print(f"\nTop 20 by frequency:")
    for name, count in observed.most_common(20):
        print(f"  {name:30s} {count:>8d}")

    dangerous_used = set(observed.keys()) & DANGEROUS_SYSCALLS
    if dangerous_used:
        print(f"\n*** WARNING: Dangerous syscalls observed ***")
        for name in sorted(dangerous_used):
            print(f"  {name} (called {observed[name]} times)")
        print("Consider whether these are truly needed by your workload.")
    print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', '-i', required=True,
                        help='Path to strace log file')
    parser.add_argument('--output', '-o', required=True,
                        help='Path to write seccomp profile JSON')
    parser.add_argument('--summary', '-s', action='store_true',
                        help='Print human-readable summary')
    args = parser.parse_args()

    observed = parse_strace_log(args.input)
    if not observed:
        print("ERROR: No syscalls found in strace log.", file=sys.stderr)
        print("Is the file empty or in an unexpected format?", file=sys.stderr)
        sys.exit(1)

    profile = generate_profile(observed)

    with open(args.output, 'w') as f:
        json.dump(profile, f, indent='\t')
        f.write('\n')

    print(f"Generated seccomp profile: {args.output}")
    print(f"  {len(profile['syscalls'][0]['names'])} syscalls allowed")

    if args.summary:
        print_summary(observed)


if __name__ == '__main__':
    main()
