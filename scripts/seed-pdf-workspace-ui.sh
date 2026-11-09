#!/usr/bin/env bash
# Synthetic fixture only. Reuse the existing library if already seeded.
set -euo pipefail
cd "$(dirname "$0")/.."
if python3 - <<'PY'
from pathlib import Path
import sqlite3, sys
path = Path('/tmp/papernest-pdf-workspace-ui/Library.sqlite')
if not path.exists(): sys.exit(1)
with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as db:
    sys.exit(0 if db.execute("SELECT 1 FROM items WHERE name = 'Interactive Form' AND deleted_at IS NULL").fetchone() else 1)
PY
then
    exit 0
fi
./scripts/swift.sh run papernest-seed /tmp/papernest-pdf-workspace-ui "Tests/Fixtures/Interactive Form.pdf"
