#!/usr/bin/env python3
"""
pre_install_qa_gate.py — Block handoff until the slim QA artifacts are fresh.

v4.0.0 (strip-first, pre-key): verifies that final validation, the contact sheet,
and the animation previews were produced after the current pre-key atlas.
Chroma-residue / eye-damage crop QA is gone — keying (and its QA) now happens in
the user's Codogotchi Studio tool, not in this pipeline. This gate does not replace
human review; it prevents claiming QA from validation alone before handing the
atlas to the user for keying.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


TIER_ROWS = {"codex": 9, "lite-basic": 9, "lite-enhanced": 8, "soa": 10}


def is_fresh(path: Path, atlas: Path) -> bool:
    return path.exists() and path.stat().st_mtime >= atlas.stat().st_mtime


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        raise SystemExit(f"ERROR: cannot read JSON report {path}: {exc}") from exc


def main() -> None:
    parser = argparse.ArgumentParser(description="Require fresh QA artifacts before installing a Codogotchi atlas.")
    parser.add_argument("--atlas", required=True, type=Path)
    parser.add_argument("--tier", required=True, choices=list(TIER_ROWS.keys()))
    parser.add_argument("--validation-json", type=Path, default=None)
    parser.add_argument("--contact-sheet", type=Path, default=None)
    parser.add_argument("--previews-dir", type=Path, default=None)
    args = parser.parse_args()

    atlas = args.atlas
    tier = args.tier
    validation_json = args.validation_json or atlas.parent / f"validate-{tier}.json"
    contact_sheet = args.contact_sheet or atlas.parent / f"contact-{tier}.png"
    previews_dir = args.previews_dir or atlas.parent / f"previews-{tier}"

    errors: list[str] = []
    for label, path in [
        ("atlas", atlas),
        ("validation JSON", validation_json),
        ("contact sheet", contact_sheet),
    ]:
        if not path.exists():
            errors.append(f"missing {label}: {path}")
        elif label != "atlas" and not is_fresh(path, atlas):
            errors.append(f"stale {label}: {path} is older than {atlas}")

    if previews_dir.exists():
        gifs = sorted(previews_dir.glob("*.gif"))
        expected = TIER_ROWS[tier]
        if len(gifs) < expected:
            errors.append(f"previews dir has {len(gifs)} GIF(s), expected at least {expected}: {previews_dir}")
        for gif in gifs:
            if gif.stat().st_mtime < atlas.stat().st_mtime:
                errors.append(f"stale preview GIF: {gif} is older than {atlas}")
                break
    else:
        errors.append(f"missing previews dir: {previews_dir}")

    if validation_json.exists():
        report = load_json(validation_json)
        if report.get("errors"):
            errors.append(f"validation report contains {len(report['errors'])} error(s): {validation_json}")

    if errors:
        print("FAIL — pre-key QA gate blocked handoff:")
        for error in errors:
            print(f"  - {error}")
        sys.exit(1)

    print("PASS — slim QA artifacts are present, fresh, and clean.")
    print("Next: hand the magenta-background atlas to the user to key at https://codogotchi.app/studio")


if __name__ == "__main__":
    main()
