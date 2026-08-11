"""Validate every skill directory with the upstream skills-ref reference validator.

Invoked by tests/SkillsRefValidate.Tests.ps1 via `uv`. Takes one or more skill
directory paths and prints one machine-readable line per skill:

    OK<TAB><skill-name>
    ERR<TAB><skill-name><TAB>problem text

Exit code is 0 whether or not problems are found; the caller decides severity.
A non-zero exit means the validator itself could not run.
"""

import sys
from pathlib import Path

from skills_ref import validate


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: validate_skills.py <skill-dir> [<skill-dir> ...]", file=sys.stderr)
        return 2

    for raw in argv:
        path = Path(raw)
        name = path.name
        try:
            problems = validate(path)
        except Exception as exc:  # noqa: BLE001 - report, never abort the batch
            print(f"ERR\t{name}\t{type(exc).__name__}: {exc}")
            continue

        if problems:
            for problem in problems:
                print(f"ERR\t{name}\t{problem}")
        else:
            print(f"OK\t{name}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
