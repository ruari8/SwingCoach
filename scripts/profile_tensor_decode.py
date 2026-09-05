#!/usr/bin/env python3
"""Compare current and baseline production tensor decoders in one optimized process."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    def run(command):
        result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT, timeout=300)
        with (output / 'commands.log').open('a') as log:
            log.write(json.dumps(command) + '\n' + result.stderr)
        if result.returncode:
            raise RuntimeError(f'Command failed: {command}; see commands.log')
        return result.stdout
    relative = 'SwingCoach/Models/GolfObjectDetector.swift'
    current = (ROOT / relative).read_text()
    baseline = run(['git', 'show', f'{args.baseline_ref}:{relative}'])
    extension = '\nextension CLASS { func profileDecode(_ output: MLMultiArray, size: CGSize) -> [GolfObjectDetection] { decode(output: output, orientedImageSize: size) } }\n'
    (output / 'Current.swift').write_text(current + extension.replace('CLASS', 'GolfObjectDetector'))
    baseline_class = baseline[baseline.index('nonisolated final class GolfObjectDetector'):].replace('GolfObjectDetector', 'BaselineGolfObjectDetector')
    (output / 'Baseline.swift').write_text('import AVFoundation\nimport CoreGraphics\nimport CoreML\nimport Vision\n' + baseline_class + extension.replace('CLASS', 'BaselineGolfObjectDetector'))
    binary = output / 'tensor_decode'
    run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-framework', 'CoreML', '-framework', 'Vision', '-framework', 'AVFoundation',
         str(output / 'Current.swift'), str(output / 'Baseline.swift'), str(ROOT / 'scripts/performance/TensorDecodeProbe.swift'), '-o', str(binary)])
    data = json.loads(run([str(binary), str(ROOT / 'SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage')]))
    data.update({'baselineRef': args.baseline_ref, 'baselineSHA256': hashlib.sha256(baseline.encode()).hexdigest(),
                 'currentSHA256': hashlib.sha256(current.encode()).hexdigest(), 'route': 'Mac tensor decoding; inference excluded'})
    (output / 'report.json').write_text(json.dumps(data, indent=2) + '\n')
    assert data['passed'] and all(row['resultsIdentical'] for row in data['rows'])
    for row in data['rows']:
        print(f"type={row['dataType']} padded={row['padded']}: {row['beforeMS']:.3f} -> {row['afterMS']:.3f} ms, {row['speedup']:.2f}x")
    print(f'PASS: {output / "report.json"}')


if __name__ == '__main__':
    main()
