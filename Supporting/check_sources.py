#!/usr/bin/env python3
"""Static checks for the app targets, which have no compiler here.

`PulseCore` is compiled and tested on every change, but `Pulse`,
`PulseWidgets` and `PulseWatch` need the iOS SDK and so are only ever parsed.
These checks cover the mistakes that parsing cannot catch and that the recent
rounds of bulk editing actually produced:

  1. a property referenced inside a type that never declares it
     (the nine "cannot find 'theme' in scope" errors in ActivityView)
  2. a stored property whose default references another instance member
     (PriceChart's `var tint: Color = theme.onField`)
  3. a member read off one of our namespaces that does not exist
     (fallout from renaming the palette)
  4. a file using PulseCore types without importing PulseCore
     (States.swift, after Palette moved)

It is deliberately conservative: it reports only what it can establish from
the text, and prints its false-positive reasoning rather than hiding it.

Usage:  python3 Supporting/check_sources.py
Exits non-zero if anything is found.
"""
import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_DIRS = ["Pulse", "PulseWidgets", "PulseWatch"]
CORE_DIR = "PulseCore/Sources"

app_files = [f for d in APP_DIRS for f in (ROOT / d).rglob("*.swift")]
core_files = list((ROOT / CORE_DIR).rglob("*.swift"))
text = {f: f.read_text() for f in app_files + core_files}


def strip_comments(src: str) -> str:
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return re.sub(r'//.*', '', src)


def top_level_types(src: str):
    """Yields (name, body) for each type declared at column zero."""
    lines = src.splitlines()
    decls = [
        (i, m.group(1))
        for i, line in enumerate(lines)
        if (m := re.match(r'^(?:public |internal )?(?:final )?'
                          r'(?:struct|class|enum|actor) (\w+)', line))
    ]
    for n, (start, name) in enumerate(decls):
        end = decls[n + 1][0] if n + 1 < len(decls) else len(lines)
        yield name, "\n".join(lines[start:end])


def check_undeclared_properties():
    """(1) `foo.` used inside a type that never declares `foo`."""
    watched = ["theme", "environment", "dismiss", "model", "session",
               "settings", "store", "liveActivity", "selection"]
    out = []
    for f in app_files:
        for name, body in top_level_types(text[f]):
            code = strip_comments(body)
            for w in watched:
                if not re.search(r'(?<![\w.])' + w + r'\.', code):
                    continue
                # A property-wrapper declaration carries no type annotation
                # (`@Environment(...) private var environment`), so the name
                # may be followed by a newline rather than `:` or `=`.
                declared = re.search(
                    r'(?:var|let)\s+' + w + r'\s*(?:[:={]|$)|'  # property
                    r'\b' + w + r'\s*:\s*\w|'                  # parameter
                    r'let\s*\(\s*' + w + r'\b',                # tuple binding
                    code, re.M)
                if not declared:
                    out.append(f"{f.name}:{name} uses `{w}.` but never declares it")
    return out


def check_property_defaults():
    """(2) a stored property default that reads another instance member."""
    members = ["theme", "model", "points", "event", "market", "order",
               "item", "request", "page", "book"]
    out = []
    for f in app_files:
        for n, line in enumerate(text[f].splitlines(), 1):
            m = re.match(r'\s+(?:var|let)\s+\w+\s*:\s*[\w.\[\]<>?]+\s*=\s*(.+)$', line)
            if not m:
                continue
            for member in members:
                if re.search(r'(?<![\w.])' + member + r'\.', m.group(1)):
                    out.append(f"{f.name}:{n} default value reads `{member}.` — "
                               f"instance members are unavailable in property initializers")
    return out


def namespace_members(name: str, files) -> set:
    found = set()
    for f in files:
        src = text[f]
        m = re.search(r'(?:public )?enum ' + name + r'\b[^{]*\{', src)
        if not m:
            continue
        depth, i = 1, m.end()
        while i < len(src) and depth:
            depth += (src[i] == '{') - (src[i] == '}')
            i += 1
        body = src[m.end():i]
        for pattern in (r'(?:static )?(?:let|var|func)\s+(\w+)',
                        r'(?:enum|struct|class)\s+(\w+)',
                        r'case\s+(\w+)'):
            found |= set(re.findall(pattern, body))
    return found


def check_namespace_members():
    """(3) `Palette.foo` where `foo` is not declared on Palette."""
    namespaces = {
        "Palette": core_files, "Format": core_files, "ActivityFormat": core_files,
        "Typography": app_files, "Layout": app_files, "Motion": app_files,
        "Allo": app_files,
    }
    out = []
    for ns, where in namespaces.items():
        declared = namespace_members(ns, where)
        if not declared:
            out.append(f"could not index namespace {ns} — check the pattern")
            continue
        for f in app_files + core_files:
            code = strip_comments(text[f])
            for m in re.finditer(r'(?<![\w.])' + ns + r'\.(\w+)', code):
                if m.group(1) not in declared:
                    line = code[:m.start()].count("\n") + 1
                    out.append(f"{f.name}:{line} {ns}.{m.group(1)} is not declared")
    return out


def check_imports():
    """(4) a file using PulseCore types without importing the module."""
    needle = re.compile(
        r'\bPalette\.|\bFormat\.|\bActivityFormat\.|\bQuoteEngine\.|'
        r'\bOrderValidator\.|\bTradingService\b|\bMarketActivityAttributes\b|'
        r': *(?:Market|Event|OrderBook|Position|ActivityItem|OpenOrder|MarketTrade|Holder)\b')
    out = []
    for f in app_files:
        if needle.search(strip_comments(text[f])) and \
                not re.search(r'^import PulseCore', text[f], re.M):
            out.append(f"{f.name} uses PulseCore types without `import PulseCore`")
    return out


def check_named_themes():
    """(5) a theme looked up by a name that is not the one identity.

    `Palette.theme(named:)` answers with the single brand theme whatever
    string it is handed, so a leftover id from the old nine-theme palette
    compiles, runs, and looks almost right. Four onboarding pages already
    shipped identical once for exactly this reason. Nothing in the type
    system can catch it, so it is caught here.
    """
    out = []
    for f in app_files:
        code = strip_comments(text[f])
        for m in re.finditer(r'theme\(named:\s*"(\w+)"', code):
            if m.group(1) != "brand":
                line = code[:m.start()].count("\n") + 1
                out.append(f"{f.name}:{line} theme(named: \"{m.group(1)}\") — "
                           f"there is one identity; use Palette.brand")
    return out


def main() -> int:
    checks = [
        ("undeclared properties", check_undeclared_properties),
        ("illegal property defaults", check_property_defaults),
        ("unknown namespace members", check_namespace_members),
        ("missing PulseCore imports", check_imports),
        ("stale theme ids", check_named_themes),
    ]
    total = 0
    for label, fn in checks:
        found = list(dict.fromkeys(fn()))
        status = f"{len(found)} issue(s)" if found else "clean"
        print(f"{label:30s} {status}")
        for item in found:
            print(f"   {item}")
        total += len(found)

    print("-" * 46)
    print(f"{len(app_files)} app files, {len(core_files)} core files, {total} issue(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
