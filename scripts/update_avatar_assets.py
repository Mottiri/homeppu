from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "functions" / "scripts" / "register-avatar-parts.js"


def main() -> int:
    if not SCRIPT.exists():
        print(f"Script not found: {SCRIPT}", file=sys.stderr)
        return 1

    cmd = ["node", str(SCRIPT), *sys.argv[1:]]
    print("Delegating to register-avatar-parts.js")
    result = subprocess.run(cmd, cwd=ROOT, check=False)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
