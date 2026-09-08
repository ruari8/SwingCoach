#!/usr/bin/env python3
"""Replay a private affected clip's decoded PTS through production Swift diagnostics."""
import argparse
import json
from pathlib import Path
import subprocess
import shutil
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('clip', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='issue28-cadence-') as temporary:
    scratch = Path(temporary)
    data = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_frames',
        '-show_entries', 'frame=best_effort_timestamp_time', '-of', 'json', str(args.clip)], text=True))
    times = [float(f['best_effort_timestamp_time']) for f in data['frames']]
    (scratch / 'timestamps.json').write_text(json.dumps(times))
    subprocess.run(['swiftc', '-module-cache-path', str(scratch / 'modules'),
                    str(root / 'SwingCoach/Models/CaptureCadenceDiagnostics.swift'),
                    str(root / 'scripts/diagnostics/CaptureCadenceProbe.swift'),
                    '-o', str(scratch / 'probe')], check=True)
    subprocess.run([str(scratch / 'probe'), str(scratch / 'timestamps.json'),
                    str(scratch / "results")], check=True)
    shutil.copytree(scratch / "results", args.output, dirs_exist_ok=True)
