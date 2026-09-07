"""Read the real app files and Simulator Photos database after each UI phase."""
import json
from pathlib import Path
import sqlite3
import sys

phase, container, photos_path, summary_path = sys.argv[1:]
summary = json.loads(Path(summary_path).read_text())
assert summary['passedTests'] == (3 if phase == 'off' else 1), summary
assert summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
with sqlite3.connect(f"file:{Path(photos_path).parents[2] / 'Library/TCC/TCC.db'}?mode=ro", uri=True) as db:
    authorization = dict(db.execute("SELECT service, auth_value FROM access WHERE client = 'Pear.ai.SwingCoach'"))
assert authorization['kTCCServicePhotosAdd'] == (0 if phase == 'off' else 2), authorization
root = Path(container)
swings = json.loads((root / 'Documents/swing_library.json').read_text())
personal = [s for s in swings if not s.get('isReference', False)]
local = [s for s in personal if not s['photoAssetID']]
photos = [s for s in personal if s['photoAssetID']]
assert len(local) == 2, personal  # Auto local clip was deleted through review.
assert len(photos) == (3 if phase == 'on' else 0), personal
for swing in personal:
    clip = root / 'Library/Application Support/SwingVideos' / swing['localVideoFilename']
    assert clip.is_file() and clip.stat().st_size > 0, clip
if Path(photos_path).exists():
    with sqlite3.connect(f'file:{photos_path}?mode=ro', uri=True) as db:
        count = db.execute('SELECT COUNT(*) FROM ZASSET WHERE ZTRASHEDSTATE = 0').fetchone()[0]
else:
    count = 0
assert count == (3 if phase == 'on' else 0), count
print(json.dumps({'phase': phase, 'local_only_clips': len(local), 'photos_backed_clips': len(photos), 'system_photos_assets': count, 'all_local_files_present': True, 'photos_authorization_raw': authorization}, indent=2))
