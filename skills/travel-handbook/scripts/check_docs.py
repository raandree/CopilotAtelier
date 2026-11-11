# /// script
# requires-python = ">=3.11"
# dependencies = ["ruamel.yaml>=0.18", "tzdata"]
# ///
"""Check two-language Markdown documents: links, anchors, reference labels, twins.

For every Markdown file under the given paths the script reports:

- local links, images, and GPX or other assets whose file does not exist,
- links to a drive, an absolute path, or a share on another host, reported
  without touching the file system,
- links to a #heading that does not exist, using GitHub's anchor rule: lower
  case, punctuation and symbols (emoji too) dropped, letters of every script
  kept (Cyrillic stays) along with the variation selector U+FE0F, spaces
  turned into hyphens, and -1, -2, ... appended to repeated headings,
- reference labels that are used but not defined, or defined but not used
  (markdownlint does not catch undefined labels),
- a primary-language file name.md and its twin name.<lang>.md that differ in
  heading levels, table rows, list items, callouts, link reference
  definitions, images, or local link targets (language suffixes such as
  .de.md and .de.png count as the same target).

Fenced code, inline code, and HTML comments are ignored.
"""
from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote

sys.dont_write_bytecode = True  # an installed Skill folder must not collect __pycache__
import trip  # noqa: E402

USAGE = """examples (from the repository root):
  uv run skills/travel-handbook/scripts/check_docs.py --config handbook/trip.yaml
  uv run skills/travel-handbook/scripts/check_docs.py --languages en,de docs README.md

stdout: one problem per line, then a summary line."""

MAX_PRINTED = 200  # problem lines printed before the rest is only counted: bounded output
FENCE_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})")
COMMENT = re.compile(r"<!--.*?-->", re.S)
INLINE_CODE = re.compile(r"(`+)(?!`)(.+?)(?<!`)\1(?!`)")
HEADING = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*$")
CLOSING_HASHES = re.compile(r"(?:^|[ \t]+)#+$")
HTML_ANCHOR = re.compile(r"<a\s[^>]*?\b(?:id|name)\s*=\s*[\"']([^\"']+)[\"']", re.I)
DEFINITION = re.compile(r"^ {0,3}\[([^\]]+)\]:[ \t]*(<[^>\n]*>|\S+)", re.M)
INLINE_LINK = re.compile(r"\]\(\s*(<[^>\n]*>|[^)\s]+)(?:\s+(?:\"[^\"\n]*\"|'[^'\n]*'|\([^)\n]*\)))?\s*\)")
IMAGE = re.compile(r"!\[[^\]\n]*\]\(\s*(<[^>\n]*>|[^)\s]+)")
FULL_REFERENCE = re.compile(r"\]\[([^\]\n]+)\]")
COLLAPSED_REFERENCE = re.compile(r"\[([^\[\]\n]+)\]\[\]")
SHORTCUT_REFERENCE = re.compile(r"(?<![\]\\])\[([^\[\]\n]+)\](?![(\[:])")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s")
EXTERNAL = re.compile(r"^(?:[a-z][a-z0-9+.-]+:|//)", re.I)  # one letter before ":" is a drive
# A drive letter, a root, or a share on another host (\\host, also spelled /\host or \/host,
# or //host once unquoted): on Windows an existence check would contact that host over SMB or
# WebDAV and send the user's NTLM credentials, so such links fail before any file access.
FOREIGN_PATH = re.compile(r"[A-Za-z]:|[\\/]")
ALERT = re.compile(r"^!\w+$")
TASK_BOXES = {" ", "x", "X"}
SKIPPED_FOLDERS = {"node_modules"}
MAX_SHOWN = 3  # differing items named per twin problem; the rest is counted


def strip_fences(text: str) -> str:
    """Blank out fenced code blocks, keeping the line count."""
    result = []
    fence = None
    for line in text.split("\n"):
        if fence is None:
            match = FENCE_OPEN.match(line)
            if match:
                fence = match.group(1)
                result.append("")
                continue
            result.append(line)
            continue
        stripped = line.strip()
        if len(stripped) >= len(fence) and set(stripped) == {fence[0]}:
            fence = None
        result.append("")
    return "\n".join(result)


def without_comments(text: str) -> str:
    return COMMENT.sub(lambda match: "\n" * match.group(0).count("\n"), text)


def prose(text: str) -> str:
    """The text without fenced code, HTML comments, and inline code."""
    return "\n".join(INLINE_CODE.sub("", line)
                     for line in strip_fences(without_comments(text)).split("\n"))


def _drop_emphasis_underscores(text: str) -> str:
    def keep(match: re.Match) -> str:
        before = text[match.start() - 1] if match.start() > 0 else ""
        after = text[match.end()] if match.end() < len(text) else ""
        return match.group(0) if before.isalnum() and after.isalnum() else ""

    return re.sub(r"_+", keep, text)


def slug(heading: str) -> str:
    """Return the anchor GitHub generates for a heading's text."""
    text = heading.strip()
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    parts = re.split(r"(`+[^`]*`+)", text)
    text = "".join(part.strip("`") if part.startswith("`") else _drop_emphasis_underscores(part)
                   for part in parts).lower()
    kept = "".join(char for char in text
                   if char in "- " or unicodedata.category(char)[0] in "LM"
                   or unicodedata.category(char) in ("Nd", "Pc"))
    return kept.replace(" ", "-")


def headings(text: str) -> list[tuple[int, str]]:
    """Level and text of every ATX heading outside fenced code."""
    result = []
    for line in strip_fences(without_comments(text)).split("\n"):
        match = HEADING.match(line)
        if match:
            title = CLOSING_HASHES.sub("", match.group(2)).strip()
            result.append((len(match.group(1)), title))
    return result


def anchors(path: Path) -> set[str]:
    """Every anchor a Markdown file offers: heading slugs and explicit HTML anchors."""
    text = path.read_text(encoding="utf-8")
    seen: dict[str, int] = {}
    result = set()
    for _, title in headings(text):
        base = slug(title)
        count = seen.get(base, 0)
        seen[base] = count + 1
        result.add(base if count == 0 else f"{base}-{count}")
    result.update(HTML_ANCHOR.findall(strip_fences(text)))
    return result


def _label(text: str) -> str:
    return " ".join(text.split()).lower()


def _target(raw: str) -> str:
    return raw[1:-1] if raw.startswith("<") and raw.endswith(">") else raw


class _Run:
    """One check over a set of files, with a per-run cache of anchors."""

    def __init__(self, languages: list[str]) -> None:
        self.languages = languages
        others = "|".join(re.escape(lang) for lang in languages[1:])
        self.suffix = re.compile(rf"\.({others})(\.[A-Za-z0-9]+)$") if others else None
        self.cache: dict[Path, set[str]] = {}

    def anchors(self, path: Path) -> set[str]:
        key = path.resolve()
        if key not in self.cache:
            self.cache[key] = anchors(path)
        return self.cache[key]

    def neutral(self, target: str) -> str:
        """Map a local link target to its language-neutral form, without the anchor."""
        file_part = unquote(target.partition("#")[0])
        return self.suffix.sub(r"\2", file_part) if self.suffix else file_part

    def links(self, path: Path, text: str) -> list[str]:
        problems = []
        name = trip.display_path(path)
        body = prose(text)
        definitions = DEFINITION.findall(strip_fences(without_comments(text)))
        targets = [_target(raw) for raw in INLINE_LINK.findall(body)]
        targets += [_target(raw) for label, raw in definitions if not label.startswith("^")]
        for target in dict.fromkeys(targets):
            if EXTERNAL.match(target):
                continue
            file_part, _, anchor = target.partition("#")
            local = unquote(file_part)
            if FOREIGN_PATH.match(local):
                problems.append(f"{name}: absolute or network path {target}; link relative to "
                                "the document")
                continue
            dest = path.parent / local if file_part else path
            if not dest.exists():
                problems.append(f"{name}: missing file {target}")
            elif anchor and dest.suffix.lower() == ".md" and unquote(anchor) not in self.anchors(dest):
                problems.append(f"{name}: missing heading #{anchor} in {dest.name}")
        defined = {_label(label) for label, _ in definitions}
        used = {_label(label) for label in FULL_REFERENCE.findall(body)}
        used |= {_label(label) for label in COLLAPSED_REFERENCE.findall(body)}
        used |= {_label(label) for label in SHORTCUT_REFERENCE.findall(body)
                 if label not in TASK_BOXES and not ALERT.match(label)}
        problems += [f"{name}: undefined reference [{label}]" for label in sorted(used - defined)]
        problems += [f"{name}: unused definition [{label}]" for label in sorted(defined - used)]
        return problems

    def profile(self, text: str) -> dict[str, object]:
        """Describe a file's structure in terms both languages share."""
        body = strip_fences(without_comments(text))
        lines = body.split("\n")
        code_free = prose(text)
        definitions = DEFINITION.findall(body)
        local = [_target(raw) for raw in INLINE_LINK.findall(code_free)]
        local += [_target(raw) for label, raw in definitions if not label.startswith("^")]
        return {
            "heading levels": [level for level, _ in headings(text)],
            "table rows": sum(line.lstrip().startswith("|") for line in lines),
            "list items": sum(bool(LIST_ITEM.match(line)) for line in lines),
            "callouts": sum(line.lstrip().startswith(">") and not previous.lstrip().startswith(">")
                            for previous, line in zip([""] + lines[:-1], lines, strict=True)),
            "link definitions": sorted(_label(label) for label, _ in definitions),
            "images": sorted(self.neutral(_target(raw)) for raw in IMAGE.findall(code_free)
                             if not EXTERNAL.match(_target(raw))),
            "link targets": sorted({self.neutral(target) for target in local
                                    if not EXTERNAL.match(target) and self.neutral(target)}),
        }

    def twins(self, files: list[Path]) -> tuple[list[str], int]:
        problems = []
        pairs = 0
        primary_lang = self.languages[0]
        for path in files:
            match = self.suffix.search(path.name) if self.suffix else None
            if match and match.group(2) == ".md":
                original = path.with_name(path.name[:match.start()] + ".md")
                if not original.exists():
                    problems.append(f"{trip.display_path(path)}: no {primary_lang} original "
                                    f"{original.name}")
                continue
            mine = self.profile(path.read_text(encoding="utf-8"))
            for lang in self.languages[1:]:
                twin = path.with_name(f"{path.stem}.{lang}.md")
                if not twin.exists():
                    problems.append(f"{trip.display_path(path)}: twin {twin.name} is missing")
                    continue
                pairs += 1
                theirs = self.profile(twin.read_text(encoding="utf-8"))
                for key, value in mine.items():
                    if theirs[key] != value:
                        detail = _difference(value, theirs[key], primary_lang, lang)
                        problems.append(f"{trip.display_path(path)} / {twin.name}: {key} differ "
                                        f"({detail})")
        return problems, pairs


def _difference(mine: object, theirs: object, primary: str, other: str) -> str:
    if isinstance(mine, int):
        return f"{primary} {mine}, {other} {theirs}"
    if all(isinstance(item, int) for item in [*mine, *theirs]):
        return f"{primary} {' '.join(map(str, mine))}; {other} {' '.join(map(str, theirs))}"
    only_mine = [item for item in mine if item not in theirs]
    only_theirs = [item for item in theirs if item not in mine]

    def show(items: list) -> str:
        shown = ", ".join(map(str, items[:MAX_SHOWN]))
        return shown + (f", +{len(items) - MAX_SHOWN} more" if len(items) > MAX_SHOWN else "")

    return f"only in {primary}: {show(only_mine) or '-'}; only in {other}: {show(only_theirs) or '-'}"


def collect(paths: list[Path]) -> list[Path]:
    """Markdown files in the given files and folders, skipping hidden folders."""
    files: dict[Path, Path] = {}
    for path in paths:
        if path.is_dir():
            for file in sorted(path.rglob("*.md")):
                folders = file.relative_to(path).parts[:-1]
                if not any(part.startswith(".") or part in SKIPPED_FOLDERS for part in folders):
                    files.setdefault(file.resolve(), file)
        elif path.is_file() and path.suffix.lower() == ".md":
            files.setdefault(path.resolve(), path)
    return sorted(files.values(), key=lambda file: file.as_posix())


def check(paths: list[Path], languages: list[str]) -> list[str]:
    """Return every problem found in the Markdown files under paths."""
    problems, _, _ = _check(paths, languages)
    return problems


def _check(paths: list[Path], languages: list[str]) -> tuple[list[str], int, int]:
    files = collect(paths)
    if not files:
        shown = ", ".join(trip.display_path(path) for path in paths)
        return [f"no Markdown files found in {shown}"], 0, 0
    run = _Run(languages)
    problems = []
    for path in files:
        problems += run.links(path, path.read_text(encoding="utf-8"))
    twin_problems, pairs = run.twins(files)
    return problems + twin_problems, len(files), pairs


def main(argv: list[str] | None = None) -> int:
    trip.configure_console()
    parser = trip.argument_parser(__doc__.split("\n")[0], USAGE)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--config", type=Path,
                        help="trip configuration: languages and paths.docs come from it")
    source.add_argument("--languages",
                        help="comma-separated language codes, primary first, e.g. en,de")
    parser.add_argument("paths", nargs="*", type=Path,
                        help="Markdown files or folders (default: paths.docs of the "
                             "configuration, else the current folder)")
    args = parser.parse_args(argv)
    if args.config is not None:
        try:
            config = trip.load_config(args.config)
        except trip.ConfigError as error:
            trip.report(error)
            return trip.EXIT_CONFIG
        languages, defaults = config.languages, config.paths.docs
    else:
        languages = [code.strip() for code in args.languages.split(",") if code.strip()]
        if (not languages or len(set(languages)) != len(languages)
                or not all(trip.LANGUAGE_PATTERN.fullmatch(code) for code in languages)):
            trip.log(f"error: --languages expects distinct codes such as en,de; "
                     f"got {args.languages!r}")
            return trip.EXIT_CONFIG
        defaults = [Path.cwd()]
    missing = [path for path in args.paths if not path.exists()]
    if missing:
        trip.log(f"error: path not found: {', '.join(path.as_posix() for path in missing)}")
        return trip.EXIT_CONFIG
    problems, documents, pairs = _check(args.paths or defaults, languages)
    for problem in problems[:MAX_PRINTED]:
        print(problem)
    if len(problems) > MAX_PRINTED:
        print(f"... and {len(problems) - MAX_PRINTED} more")
    print(f"{documents} documents, {pairs} twin pairs: {len(problems)} "
          f"problem{'' if len(problems) == 1 else 's'}")
    return trip.EXIT_CHECK if problems else trip.EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
