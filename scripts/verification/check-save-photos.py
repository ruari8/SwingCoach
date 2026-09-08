"""Read the real app files and Simulator Photos database after each UI phase."""
import json
from pathlib import Path
import sqlite3
import sys

def active_assets(path):
    with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as db:
        return {row[0].upper() for row in db.execute('SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0')}


if sys.argv[1] == '--baseline':
    Path(sys.argv[3]).write_text(json.dumps(sorted(active_assets(sys.argv[2])), indent=2))
    sys.exit(0)

phase, container, photos_path, summary_path, baseline_path, expected_local_count = sys.argv[1:]
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
assert len(local) == int(expected_local_count), personal
assert len(photos) == (3 if phase == 'on' else 0), personal
for swing in personal:
    clip = root / 'Library/Application Support/SwingVideos' / swing['localVideoFilename']
    assert clip.is_file() and clip.stat().st_size > 0, clip
before = set(json.loads(Path(baseline_path).read_text()))
after = active_assets(photos_path)
assert before <= after, 'Verification removed a pre-existing Photos asset'
created = after - before
expected = {s['photoAssetID'].split('/')[0].upper() for s in photos}
assert created == expected, {'unexpected': sorted(created - expected), 'missing': sorted(expected - created)}
print(json.dumps({'phase': phase, 'local_only_clips': len(local), 'photos_backed_clips': len(photos),
                  'baseline_photos_assets': len(before), 'new_photos_assets': len(created),
                  'all_local_files_present': True, 'photos_authorization_raw': authorization}, indent=2))
