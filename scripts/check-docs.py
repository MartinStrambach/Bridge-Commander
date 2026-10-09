#!/usr/bin/env python3
"""Check that the agent-facing docs still describe the code.

- Every `identifier` in backticks in CLAUDE.md and the READMEs (a type, a
  member, a function like `runGit(arguments:at:)`, a dotted path like
  `RepositoryRowReducer.State`) must appear in the repository's sources.
- Every backticked file name (`GitService.swift`) and repository path
  (`Packages/AppUI/README.md`, `scripts/build.sh`) must exist.
- CLAUDE.md stays within its line budget: it is loaded into every session, so a
  package's design notes belong in that package's README.

Names that are not ours (Apple private API, other repositories) go in
scripts/check-docs.allow, one per line.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLAUDE_MD_MAX_LINES = 130

SOURCE_SUFFIXES = {".swift", ".m", ".h", ".c", ".metal", ".sh", ".py", ".pbxproj", ".plist", ".entitlements", ".json"}
SOURCE_NAMES = {"Makefile", "Package.swift"}
FILE_SUFFIXES = (".swift", ".md", ".sh", ".py", ".plist", ".json", ".pbxproj", ".entitlements", ".xcconfig", ".metal", ".m", ".h")

IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*(\([A-Za-z0-9_:]*\))?$")


def tracked_files():
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [line for line in out.splitlines() if line]


def docs(files):
    return [f for f in files if f == "CLAUDE.md" or (f.endswith("/README.md") and f.count("/") >= 1)]


def is_checked_identifier(span):
    """camelCase/PascalCase names, dotted members and calls; plain words are prose."""
    if not IDENTIFIER.match(span):
        return False
    name = span.split("(")[0]
    return "(" in span or "." in name or re.search(r"[a-z][A-Z]|^[A-Z][a-z]+[A-Z]", name) is not None


def components(span):
    """`Type.member(label:)` -> ["Type", "member"]; each must occur in the sources."""
    return [c for c in span.split("(")[0].split(".") if c]


def main():
    files = tracked_files()
    tracked = set(files)
    basenames = {Path(f).name for f in files}
    corpus = "\n".join(
        (ROOT / f).read_text(errors="ignore")
        for f in files
        if (Path(f).suffix in SOURCE_SUFFIXES or Path(f).name in SOURCE_NAMES) and (ROOT / f).is_file()
    )

    allow_file = ROOT / "scripts" / "check-docs.allow"
    allowed = set()
    if allow_file.exists():
        allowed = {
            line.strip() for line in allow_file.read_text().splitlines() if line.strip() and not line.startswith("#")
        }

    problems = []
    for doc in docs(files):
        text = (ROOT / doc).read_text()
        # Fenced code blocks are commands and samples, not references.
        text = re.sub(r"```.*?```", "", text, flags=re.S)
        for lineno, line in enumerate(text.splitlines(), 1):
            for span in re.findall(r"`([^`\n]+)`", line):
                span = span.strip()
                # Allowed names, and placeholders like `XxxClient` in recipes.
                if span in allowed or "Xxx" in span:
                    continue
                if "/" in span and re.match(r"^(Packages|scripts|BridgeCommander)/[^\s*<>]+$", span):
                    path = span.rstrip("/")
                    if path not in tracked and not any(t.startswith(path + "/") for t in tracked):
                        problems.append(f"{doc}:{lineno}: path `{span}` does not exist")
                elif "/" not in span and " " not in span and span.endswith(FILE_SUFFIXES):
                    # A file the app writes at run time is named in the sources instead.
                    if span not in basenames and span not in corpus:
                        problems.append(f"{doc}:{lineno}: file `{span}` does not exist")
                elif is_checked_identifier(span):
                    # A substring match also accepts the Reducer+View pairs named
                    # by their stem (`TerminalButton`) and names built into longer
                    # ones (`GSEventTypeDeviceOrientationChanged`).
                    missing = [c for c in components(span) if c not in corpus and c not in allowed]
                    if missing:
                        problems.append(f"{doc}:{lineno}: `{span}`: {', '.join(missing)} not found in the sources")

    claude_lines = len((ROOT / "CLAUDE.md").read_text().splitlines())
    if claude_lines > CLAUDE_MD_MAX_LINES:
        problems.append(
            f"CLAUDE.md: {claude_lines} lines, over its budget of {CLAUDE_MD_MAX_LINES}. "
            "Move package-specific notes to Packages/<Name>/README.md"
        )

    for p in problems:
        print(p)
    if not problems:
        print("Docs: ok")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
