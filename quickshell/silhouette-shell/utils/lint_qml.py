#!/usr/bin/env python3
"""
Guard the QML tree against the three silent bug classes that have actually
cost this shell something. Every check here exists because the failure mode
was invisible: no error, no warning, the UI just quietly did not update.

  1. rich-text     A Text block binds a string the shell does not own (a
                   window title, an MPRIS track, clipboard contents, an SSID,
                   a credential, a package manager's output) without
                   `textFormat: Text.PlainText`, so markup in that string
                   renders as rich text.
  2. bound-scope   Under `pragma ComponentBehavior: Bound`, a handler inside a
                   nested object cannot resolve a bare identifier that belongs
                   to an enclosing object other than the component root. It
                   throws a ReferenceError at runtime and the surrounding
                   feature silently does nothing.
  3. untracked     A binding whose value comes from something that does not
                   notify — the wall clock, or a `var` object mutated in place
                   — never re-evaluates on its own. QML *does* capture a
                   property read made inside a called function, so calling a
                   helper is fine; reading a clock through one is not.

Exit code 0 when clean, 1 when anything is reported, so it can gate a commit.

Usage:
  utils/lint_qml.py [--all] [paths...]

  --all   Report every non-literal `text:` binding without textFormat instead
          of only the externally-sourced ones. Useful when auditing a new
          file; noisy for the whole tree.
"""

import argparse
import pathlib
import re
import sys

# Property bindings whose right-hand side may be a bare function call on an id.
CALL_BINDING = re.compile(r'^[ \t]*(?:readonly\s+)?property\s+\w+\s+(\w+)\s*:[ \t]*([^\n]*)$',
                          re.M)
OBJECT_OPEN = re.compile(r'([A-Z][\w.]*)\s*\{')
ID_DECL = re.compile(r'^\s*id\s*:\s*(\w+)\s*$')
PROP_DECL = re.compile(r'^\s*(?:readonly\s+)?property\s+(?:var|int|real|bool|string|double|color|url|size|point|rect)\s+(\w+)')
HANDLER = re.compile(r'^\s*(on[A-Z]\w*)\s*:\s*(\{?|function\s*\()')

# Text that comes from outside the shell. Deliberately narrow and qualified:
# a guard that cries wolf over the shell's own `label:` bindings gets ignored,
# so only sources that are genuinely another program's data are listed.
EXTERNAL_TOKENS = re.compile(
    r'(Players\.(title|artist)|'
    r'Polkit\.(message|action)|'
    r'Notifs\.replyAction|'
    r'win(ow)?Row\.win\.(title|cls)|'
    r'erow\.title|'
    r'mrow\.entryData\.text|'
    r'row\.entry\.(preview|label)|'
    r'row\.ssid|'
    r'cr\.(value|label)|'
    r'brow\.kbCmd|'
    r'result\.modelData\.output|'
    r'con\.name|dev\.modelData|dev\.meta|'
    r'profile\.realName|'
    r'title$)'
)

# Namespaces whose members are pure functions of their arguments: nothing to
# track, so calling one never leaves a binding stale. Reporting them was 90% of
# the noise and trains you to ignore the check.
PURE_NAMESPACES = {
    'Math', 'Qt', 'JSON', 'Object', 'Array', 'Date', 'Number', 'String',
    'Boolean', 'RegExp', 'parseInt', 'parseFloat', 'isNaN', 'isFinite',
    'encodeURIComponent', 'decodeURIComponent', 'console', 'qsTr', 'qsTrId',
}

# Methods of built-in JS objects. `list.find(...)` reads `list`, so the binding
# *is* tracked; the call shape is not the problem. Only QML-defined functions
# hide their reads, and those are the ones worth reporting.
BUILTIN_METHODS = {
    'find', 'filter', 'map', 'forEach', 'some', 'every', 'reduce', 'indexOf',
    'lastIndexOf', 'includes', 'join', 'slice', 'splice', 'sort', 'reverse',
    'concat', 'push', 'pop', 'shift', 'unshift', 'keys', 'values', 'entries',
    'flat', 'flatMap', 'at', 'fill', 'split', 'replace', 'replaceAll', 'match',
    'search', 'toUpperCase', 'toLowerCase', 'trim', 'padStart', 'padEnd',
    'repeat', 'substring', 'substr', 'charAt', 'charCodeAt', 'startsWith',
    'endsWith', 'toString', 'toFixed', 'getFullYear', 'getMonth', 'getDate',
    'getDay', 'getHours', 'getMinutes', 'getSeconds', 'getTime', 'getTimezoneOffset',
    'setFullYear', 'setMonth', 'setDate', 'setHours', 'setMinutes', 'setSeconds',
    'setTime', 'test', 'exec', 'hasOwnProperty', 'toJSON', 'call', 'apply', 'bind',
    'floor', 'ceil', 'round', 'abs', 'min', 'max', 'pow', 'sqrt', 'random',
}

# ids that own data the shell produced itself; safe to render as-is.
INTERNAL_IDS = re.compile(r'^(root|inbox|nrow|col|host|harness|bar|pill|face|toast|row|item|'
                          r'tile|card|page|surface|btn|chip|cel|wrap|stack)$')

# `import "utils/launcher/fuzzy.js" as Fuzzy` — a plain JS namespace. Every
# member is a pure function of its arguments, so nothing can go stale.
JS_NAMESPACE = re.compile(r'^\s*import\s+"[^"]+"\s+as\s+(\w+)', re.M)


def strip_comments(src):
    """Blank out comments while preserving offsets and line structure."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(c if c == '\n' else ' ' for c in src[i:j]))
            i = j
        elif src[i] in '"\'':
            q = src[i]
            j = i + 1
            while j < n and src[j] != q:
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
            out.append(src[i:j])
            i = j
        else:
            out.append(src[i])
            i += 1
    return ''.join(out)


def block_at(src, brace):
    """Return (body, end) for the brace-matched block starting at `brace`."""
    depth, j = 0, brace
    while j < len(src):
        if src[j] == '{':
            depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0:
                return src[brace + 1:j], j
        j += 1
    return src[brace:], len(src)


def line_of(src, idx):
    return src.count('\n', 0, idx) + 1


def check_plain_text(src, path, report, all_mode):
    """Text blocks binding a non-literal string without textFormat."""
    for m in re.finditer(r'\bText\s*\{', src):
        body, _ = block_at(src, m.end() - 1)
        if 'textFormat' in body:
            continue
        tm = re.search(r'^\s*text\s*:\s*(.+?)\s*$', body, re.M)
        if not tm:
            continue
        expr = tm.group(1)
        if expr.startswith(('"', "'", 'qsTr')) or '"""' in expr:
            continue
        if not all_mode and not EXTERNAL_TOKENS.search(expr):
            continue
        report(path, line_of(src, m.start()), 'rich-text', f'text: {expr[:60]}')


def object_members(src, start, end):
    """ids and property names declared *directly* in one object block.

    Depth-aware: a nested object's own `id:`/properties belong to it, not to
    the object that encloses it, and mixing the two hides the very bug this
    check looks for.
    """
    names = set()
    depth = 0
    for line in src[start + 1:end].splitlines():
        if depth == 0:
            im = ID_DECL.match(line)
            if im:
                names.add(im.group(1))
            pm = PROP_DECL.match(line)
            if pm:
                names.add(pm.group(1))
        depth += line.count('{') - line.count('}')
    return names


def check_bound_scope(src, path, report):
    """Bare identifiers in a nested handler that belong to an enclosing object.

    Under `pragma ComponentBehavior: Bound` a nested object can still reach the
    component's root id, but nothing else from its ancestors. Reading a
    property of the object that owns the handler throws a ReferenceError at
    runtime, which is how the ffmpeg fallback ended up never starting.
    """
    if 'pragma ComponentBehavior: Bound' not in src:
        return

    root = src.find('{', src.find('pragma ComponentBehavior'))
    if root < 0:
        return
    root_body, _ = block_at(src, root)
    im = re.search(r'^\s*id\s*:\s*(\w+)', root_body, re.M)
    root_id = im.group(1) if im else None

    members = {}

    def members_of(brace):
        if brace not in members:
            members[brace] = object_members(src, brace, block_at(src, brace)[1])
        return members[brace]

    # Strings and comments are already blanked, so a brace stack is exact.
    stack = []
    handler = re.compile(r'(on[A-Z]\w*)\s*:\s*\{')
    for i, ch in enumerate(src):
        if ch == '{':
            stack.append(i)
            continue
        if ch == '}':
            if len(stack) > 1:
                stack.pop()
            continue
        if len(stack) < 3:
            continue
        # The handler name has to start exactly here: matching against a
        # lstripped window matches once per leading space and reports the
        # same handler a dozen times.
        if i and (src[i - 1].isalnum() or src[i - 1] in '_$'):
            continue
        hm = handler.match(src, i)
        if not hm:
            continue
        owner, parent = stack[-1], stack[-2]
        if parent == root:
            continue  # the root id is the documented exception
        body, _ = block_at(src, hm.end() - 1)
        scan = body
        own, inherited = members_of(owner), members_of(parent)
        local = set(re.findall(r'\b(?:var|const|let|function)\s+(\w+)', scan))
        for tm in re.finditer(r'(?<![\w.$])(\w+)', scan):
            ident = tm.group(1)
            if ident in local or ident in own:
                continue
            # `parent.foo` is the correct way to reach an ancestor member, so an
            # identifier that is the base of a qualified read is not a finding.
            # The pattern below needs a trailing guard because `(\w+)` alone
            # will happily hand back `foo` from inside `foobar`.
            if re.match(r'\s*\??\.', scan[tm.end():]):
                continue
            if ident in inherited and ident != root_id:
                report(path, line_of(src, i), 'bound-scope',
                       f'{hm.group(1)} reads enclosing "{ident}" unqualified')


def singleton_functions(src):
    """{name: body} for the functions of a `pragma Singleton` file."""
    if 'pragma Singleton' not in src:
        return None, set()
    root = src.find('{', src.find('pragma Singleton'))
    if root < 0:
        return None, set()
    _, end = block_at(src, root)
    props = object_members(src, root, end)
    body = src[root + 1:end]
    funcs = {}
    for fm in re.finditer(r'\bfunction\s+(\w+)\s*\(', body):
        brace = body.find('{', fm.end())
        if brace < 0:
            continue
        funcs[fm.group(1)] = block_at(body, brace)[0]
    return funcs, props


def reads_state(body, props, root_id):
    """True when a function body depends on a source QML cannot track.

    Two such sources exist, and both are silent:

      - a clock (`Date.now()`), which changes without anything changing;
      - a `var` property that is mutated in place (`root.map["k"] = v`) rather
        than reassigned, so no notify signal is ever emitted.

    A plain read of a notifying property is *not* included: QML captures
    property reads made inside a called function, so `Theme.joinArtists(a, b)`
    and `Notifs.entryExpanded(id)` both track correctly. Verified against
    Quickshell rather than assumed — that assumption is what made an earlier
    version of this check report every helper call in the tree.
    """
    if re.search(r'\bDate\s*\.\s*now\s*\(|\bperformance\s*\.\s*now\s*\(', body):
        return True
    # `root.x.y = ...` or `root.x[k] = ...` writes a member of `x` in place.
    for tm in re.finditer(r'(?<![\w.$])%s\s*\.\s*(\w+)\s*(?:\[[^\]]*\]|\.\s*\w+)\s*=[^=]' % re.escape(root_id), body):
        if tm.group(1) in props:
            return True
    return False


def load_source(path):
    try:
        return strip_comments(path.read_text())
    except (OSError, UnicodeDecodeError):
        return None


def index_singleton(index, name, src):
    funcs, props = singleton_functions(src)
    if funcs is None:
        return
    brace = src.find('{', src.find('pragma Singleton'))
    if brace < 0:
        return
    im = re.search(r'^\s*id\s*:\s*(\w+)', block_at(src, brace)[0], re.M)
    index[name] = (funcs, props, im.group(1) if im else name)


def build_singletons(files):
    """{singleton name: (functions, own properties, root id)} reachable from `files`.

    Resolving the callee is what keeps the `untracked` check honest: without it
    every `Something.helper(...)` looks alike, and the check degenerates into
    noise that has to be ignored — which is the same as not having it.

    Sibling directories are pulled in through each file's qmldir so that linting
    a single file still resolves the singletons it calls.
    """
    index = {}
    sources = {}
    seen = set()

    def note(path):
        if path in seen:
            return
        seen.add(path)
        src = load_source(path)
        if src is None:
            return None
        sources[path] = src
        if 'pragma Singleton' in src:
            index_singleton(index, path.stem, src)
        return src

    for path in files:
        note(path)
        for qmdir in sorted(path.parent.glob('qmldir')):
            try:
                lines = qmdir.read_text().splitlines()
            except OSError:
                continue
            for line in lines:
                parts = line.split()
                if len(parts) < 3 or parts[0] != 'singleton':
                    continue
                # A qmldir line (`singleton Notifs 1.0 Notifs.qml`) is how call
                # sites spell the singleton, so index the alias under that name.
                # The file is the last field; the version sits in between.
                alias, target = parts[1], parts[-1]
                cand = qmdir.parent / target
                if alias in index or not target.endswith('.qml') or not cand.exists():
                    continue
                src = note(cand)
                if src is not None:
                    index_singleton(index, alias, src)
    return index


def check_untracked(src, path, report, singletons):
    """Bindings that call a QML function whose body reads state the caller never names.

    A binding like `readonly property string artist: Theme.joinArtists(a, b)`
    only re-evaluates when `a` or `b` changes. If the function also consults a
    property of its own singleton, nothing in the binding names that property,
    so the value silently goes stale.

    Exempt because they cannot go stale: pure namespaces (`Math.min`), methods
    of built-in JS objects (`list.find(...)` *does* read `list`, so it is
    tracked), `import "..." as X` JS namespaces, and singletons whose function
    body turns out to touch none of their own state.
    """
    js_ns = set(JS_NAMESPACE.findall(src))
    for m in CALL_BINDING.finditer(src):
        expr = m.group(2)
        suspects = {}
        for tm in re.finditer(r'(?<![\w.])(\w+)\s*\.\s*(\w+)\s*\(', expr):
            target, method = tm.group(1), tm.group(2)
            if method in BUILTIN_METHODS or method in PURE_NAMESPACES:
                continue
            if INTERNAL_IDS.match(target) or target in js_ns:
                continue
            suspects.setdefault(target, set()).add(method)
        for target, methods in sorted(suspects.items()):
            entry = singletons.get(target)
            if entry is None:
                continue  # not a singleton in this tree; nothing to resolve
            funcs, props, root_id = entry
            stateful = {name for name in methods
                        if name in funcs and reads_state(funcs[name], props, root_id)}
            if not stateful:
                continue
            # A bare property read from the same target anywhere in the file is
            # the documented workaround (see Notifs.ageLabel's `void root.tick`).
            reads = [r for r in re.finditer(r'(?<![\w.])%s\s*\.\s*(\w+)' % re.escape(target), src)
                     if not src[r.end():].lstrip().startswith('(')]
            if reads:
                continue
            report(path, line_of(src, m.start()), 'untracked',
                   f'{target}.{sorted(stateful)[0]}(...) depends on a '
                   f'non-notifying source, so the binding never re-evaluates')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--all', action='store_true',
                    help='report every non-literal text binding, not just external ones')
    ap.add_argument('paths', nargs='*', default=['.'])
    args = ap.parse_args()

    findings = []

    def report(path, line, kind, detail):
        findings.append((str(path), line, kind, detail))

    files = []
    for root in args.paths or ['.']:
        p = pathlib.Path(root)
        files.extend(sorted(p.rglob('*.qml')) if p.is_dir() else [p])

    singletons = build_singletons(files)
    for path in files:
        src = load_source(path)
        if src is None:
            continue
        check_plain_text(src, path, report, args.all)
        check_bound_scope(src, path, report)
        check_untracked(src, path, report, singletons)

    if not findings:
        print(f'qml lint: clean ({len(files)} files)')
        return 0

    for path, line, kind, detail in findings:
        print(f'{path}:{line}: {kind}: {detail}')
    counts = {}
    for _, _, kind, _ in findings:
        counts[kind] = counts.get(kind, 0) + 1
    print('\n%d finding(s): %s' % (len(findings), ', '.join(f'{k}={v}' for k, v in sorted(counts.items()))))
    return 1


if __name__ == '__main__':
    sys.exit(main())