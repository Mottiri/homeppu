from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
ASSETS_DIR = ROOT / "assets" / "avatars"
TARGET = ROOT / "lib" / "core" / "constants" / "avatar_assets.dart"

PARTS = {
    "hairIds": "hair",
    "eyesIds": "eyes",
    "mouthIds": "mouth",
    "eyebrowsIds": "eyebrows",
}


def collect_ids(part_dir: Path) -> list[str]:
    if not part_dir.exists():
        raise FileNotFoundError(f"Missing directory: {part_dir}")
    ids = [p.stem for p in part_dir.glob("*.png")]
    ids = sorted(ids)
    if not ids:
        raise ValueError(f"No PNGs found in: {part_dir}")
    return ids


def update_lists(text: str, key: str, values: list[str]) -> str:
    values_literal = ", ".join([f"'{v}'" for v in values])
    replacement = f"static const List<String> {key} = [{values_literal}];"
    pattern = rf"static const List<String> {key} = \[[^\]]*\];"
    new_text, count = re.subn(pattern, replacement, text)
    if count != 1:
        raise ValueError(f"Failed to update {key} (matches={count})")
    return new_text


def main() -> int:
    if not TARGET.exists():
        print(f"Target not found: {TARGET}", file=sys.stderr)
        return 1

    text = TARGET.read_text(encoding="utf-8")
    for key, folder in PARTS.items():
        ids = collect_ids(ASSETS_DIR / folder)
        text = update_lists(text, key, ids)
        print(f"{key}: {ids}")

    TARGET.write_text(text, encoding="utf-8")
    print("Updated avatar_assets.dart")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
