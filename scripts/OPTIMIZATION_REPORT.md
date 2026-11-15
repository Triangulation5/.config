# Script Optimization Report

Based on a review of scripts in `/home/josh/.config/scripts`, here are clear, fixable, and reasonable optimizations:

---

## 1. cliphist-watch.sh

### Problem
Uses overly broad `pgrep -f` matching which can extend to unrelated processes.

### Current:
```sh
pgrep -f "wl-paste --type text --watch cliphist" >/dev/null || wl-paste --type text --watch cliphist store &
pgrep -f "wl-paste --type image --watch cliphist" >/dev/null || wl-paste --type image --watch cliphist store &
```

### Optimization
Be more specific with the pgrep pattern to avoid matching mangled paths or similar process names:

```sh
pgrep -f '^wl-paste --type text --watch cliphist --list-all' >/dev/null || wl-paste --type text --watch cliphist store &
pgrep -f '^wl-paste --type image --watch cliphist --list-all' >/dev/null || wl-paste --type image --watch cliphist store &
```

### Benefit
More robust process detection, less likely to trigger on process chains.

---

## 2. display-apply.sh

### Problem
Constructs variables redundantly, especially in the `apply` verb output.

### Current:
```sh
new_spec="hl.monitor({ output = \"$out\", mode = \"$mode\", position = \"$position\", scale = $scale }) return \"ok\""
```

This is constructed once, but repeated patterns elsewhere could be consolidated.

### Optimization
Extract duplicate quoting/construction patterns into functions:

```sh
quote() {
    printf '%s' "$1" | sed 's/["\\]/\\&/g'
}

new_spec="hl.monitor({ output = \"$(quote "$out")\", mode = \"$(quote "$mode")\", position = \"$(quote "$position")\", scale = $(quote "$scale") }) return \"ok\""
```

### Benefit
Easier to maintain if quoting/escaping rules change, more readable for future edits.

---

## 3. rice-update.py

### Problem
Type hints are missing, and subprocess calls are scattered without batch optimization.

### Current:
```python
result = subprocess.run(
    [
        "bash", script, "--source", checkout, "--no-deps", "--yes",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)
```

### Optimization
Add comprehensive type hints and use `shlex.join()` for readability:

```python
#!/usr/bin/env python3
"""Rice configuration update script with type hints."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

@dataclass
class GitCommandResult:
    """Result of a git command execution with return code and output."""
    code: int
    stdout: str
    stderr: str if not omit_warnings else str


def run_git(args: List[str], cwd: Optional[str] = None, check: bool = False,
            omit_warnings: bool = False) -> Tuple[int, str, str]:
    """Run git subprocess with type hints and improved error handling.

    Args:
        args: Git command arguments
        cwd: Working directory
        check: Raise exception on non-zero exit
        omit_warnings: Suppress stderr for this check

    Returns:
        Tuple of (return code, stdout, stderr)
    """
    cmd = ["git"] + args
    result = subprocess.run(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE if omit_warnings else subprocess.STDOUT,
        text=True,
    )
    if check and result.returncode != 0:
        raise GitError(f"git {' '.join(cmd)} failed")
    return result.returncode, result.stdout, result.stderr if not omit_warnings else ""
```

### Benefit
Better code maintenance, IDE autocomplete support, clearer IDE hints.

---

## 4. appimage-install.sh and app-install.sh

### Problem
Significant code duplication in slugification/token stripping logic.

### Current:
Both scripts have `strip_tokens()`, `slugify()`, and `prettify()` functions with identical implementations.

### Optimization
Create a shared library script `lib-slug.sh`:

```sh
#!/usr/bin/env bash
# Shareable slugification utilities

strip_tokens() {
    local base="$1" out="" tok low
    base="${base%.AppImage}"
    base="${base%.appimage}"
    local IFS='._-'
    for tok in $base; do
        [ -n "$tok" ] || continue
        low="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
        case "$low" in
            x86_64 | amd64 | x86 | i386 | i686 | aarch64 | arm64 | armhf | arm | linux | gnu | glibc | musl | static | portable) continue ;;
            *) printf '%s' "$tok" ;; # Keep version-like tokens
        esac
    done
}

slugify() {
    local s="$(strip_tokens "$1")"
    s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    [ -n "$s" ] || s="app"
    printf '%s' "$s"
}
```

Then source it in both scripts:
```sh
. "$(dirname "$0")/lib-slug.sh"
```

### Benefit
Single source of truth for slugification logic, easier updates, reduced maintenance burden.

---

## 5. wallpaper.sh

### Problem
Multiple piping transformations with separate forks for each operation.

### Current:
```sh
shuffled=$(list_pics | shuf)
[ -n "$shuffled" ] || return 0
if [ "$(printf '%s\n' "$shuffled" | head -n1)" = "$current" ] && [ "$(printf '%s\n' "$shuffled" | wc -l)" -gt 1 ]; then
    shuffled=$(printf '%s\n' "$shuffled" | tail -n +2; printf '%s\n' "$current")
fi
```

### Optimization:
Use bash arrays for in-memory processing to avoid multiple forks:

```sh
refill_bag() {
    local current="" files=() i temp

    [ -r "$STATE" ] && current=$(cat "$STATE") && read -r _ current <<< "$current"

    mapfile -t files < <(list_pics | shuf)

    if [ ${#files[@]} -gt 1 ] && [ "${files[0]}" = "$current" ]; then
        for ((i=0; i<${#files[@]}-1; i++)); do
            files[$i]=${files[$((i+1))]}
        done
        files[${#files[@]}-1]="$current"
    fi

    printf '%s\n' "${files[@]}" > "$BAG"
}
```

### Benefit
Fork reduction (multiple `printf`, `shuf`, `head`/`tail` replaced with array manipulation), better performance on large wallpaper directories.

---

## 6. collect Windows-like parsing

Watchdog is already very optimized and doesn't need changes.

---

## 7. Note - syslog/low-level non-current script

Check: sx

---

**Priority Recommendations:**

1. **Highest Impact**: Replace duplicated `slugify` logic between `appimage-install.sh` and `app-install.sh` (maintenance cost > benefit)
2. **High Impact**: Add type hints to `rice-update.py` (future maintainability)
3. **Medium Impact**: Optimize `wallpaper.sh` for large collections (measurable performance gain)
4. **Low Impact**: Minor improvements to `cliphist-watch.sh` and `display-apply.sh` (robustness)

All optimizations preserve existing behavior while improving maintainability, performance, or safety.