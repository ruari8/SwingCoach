#!/usr/bin/env python3
"""Measure production SwingLibrary methods in an isolated iOS Simulator probe app."""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.swingcoach.LibraryPerformanceProbe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runtime", default="com.apple.CoreSimulator.SimRuntime.iOS-26-3")
    parser.add_argument("--device-type", default="com.apple.CoreSimulator.SimDeviceType.iPhone-17")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    simulator = None
    report = {"passed": False, "route": "isolated Simulator model-method probe; no UI latency or phone claim"}
    def run(command, timeout=120):
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        with (output / "commands.log").open("a") as log:
            log.write(json.dumps(command) + "\n" + result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {command}; see commands.log")
        return result.stdout.strip()
    try:
        sources = [ROOT / "SwingCoach/Models/SwingClip.swift", ROOT / "SwingCoach/Models/SwingLibrary.swift",
                   ROOT / "scripts/performance/LibraryPerformanceProbe.swift"]
        source_dir = output / "source"
        source_dir.mkdir()
        hashes = {}
        for source in sources:
            shutil.copy2(source, source_dir / source.name)
            hashes[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
        report.update({"sourceHashes": hashes, "gitRevision": run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
                       "gitStatus": run(["git", "-C", str(ROOT), "status", "--short"]),
                       "xcode": run(["xcodebuild", "-version"]), "runtime": args.runtime})
        app = output / "LibraryProbe.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "LibraryProbe", "CFBundleName": "LibraryProbe",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "MinimumOSVersion": "18.6", "LSRequiresIPhoneOS": True,
            "NSPhotoLibraryUsageDescription": "Isolated library performance verification",
        }))
        sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])
        run(["xcrun", "swiftc", "-parse-as-library", "-O", "-swift-version", "5", "-default-isolation", "MainActor",
             "-sdk", sdk, "-target", "arm64-apple-ios18.6-simulator",
             *[str(source_dir / source.name) for source in sources], "-o", str(app / "LibraryProbe")])
        simulator = run(["xcrun", "simctl", "create", f"SwingCoach Library Profile {output.name}", args.device_type, args.runtime])
        report["simulator"] = simulator
        run(["xcrun", "simctl", "boot", simulator])
        run(["xcrun", "simctl", "bootstatus", simulator, "-b"])
        run(["xcrun", "simctl", "install", simulator, str(app)])
        container = Path(run(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"]))
        run(["xcrun", "simctl", "launch", simulator, BUNDLE])
        result_path = container / "Documents/profile.json"
        deadline = time.monotonic() + 120
        while not result_path.exists() and time.monotonic() < deadline:
            time.sleep(0.5)
        shutil.copy2(result_path, output / "profile.json")
        profile = json.loads((output / "profile.json").read_text())
        assert profile["passed"] and profile["mainThread"], profile
        report["passed"] = True
        for row in profile["rows"]:
            print(row["operation"], row.get("libraryCount", row.get("inputMiB")), f"median {row['timing']['medianMS']:.3f} ms", flush=True)
    finally:
        if simulator:
            subprocess.run(["xcrun", "simctl", "terminate", simulator, BUNDLE], capture_output=True)
            subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True)
            run(["xcrun", "simctl", "delete", simulator])
            devices = run(["xcrun", "simctl", "list", "devices", "--json"])
            report["simulatorDeleted"] = simulator not in devices
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {output}")


if __name__ == "__main__":
    main()
