#!/usr/bin/env python3
"""Run SwingCoach's verification areas on a disposable iOS Simulator.

Usage: scripts/verify.sh <area>... [--only TestClass[/testMethod]]... [--artifacts DIR]

Default areas (`all` runs every one):
  smoke    launch, play a synthetic clip, go back, enter Capture
  unit     every SwingCoachTests unit test
  library  sessions, selection, export, deletion, filtered collections, paging and transport
  review   fast swipes, review Lock, annotations, review unit tests
  capture  capture controls and settings, audio policy, Manual -> Trim -> Cancel, Auto review annotations
  trim     Trim review and export, partial-save retry, extra footage and the Trim clock
  storage  Save to Photos OFF and ON, local clips, Photos rows

On request only:
  stress      fast swipes over 171 clips
  console     Library paging with a scan of the app's console for framework diagnostics
  trim-clock  slow-motion playback clock probe on macOS (no Simulator)
  coach       legacy coaching flow against a local backend (needs backend/venv, the pose
              model and SwingCoach/ReferenceSwings/DaBMIbhpel9_1.mp4)

One build (build/verify/DerivedData, reused between runs) and one new Simulator serve
every area in a run; the Simulator is deleted on exit. The last line is PASS, FAIL or
BLOCKED <reason>, followed by the artifact directory.
"""
import argparse
import fcntl
import json
import os
import plistlib
import shutil
import signal
import sqlite3
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Optional

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "Pear.ai.SwingCoach"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
DERIVED_DATA = ROOT / "build/verify/DerivedData"
UI = "SwingCoachUITests"
UNIT = "SwingCoachTests"
FIXTURE_RECORDINGS = "ui-fixture-recording-*.mp4"


class Blocked(Exception):
    pass


class Failed(Exception):
    pass


@dataclass
class Step:
    name: str
    tests: list
    plan: str = "SwingCoach"
    before: Optional[Callable] = None
    after: Optional[Callable] = None
    # The after-check applies only when this selector ran in full.
    check_on: Optional[str] = None


@dataclass
class Run:
    artifacts: Path
    device: str = ""
    log: list = field(default_factory=list)
    state: dict = field(default_factory=dict)

    def container(self):
        return Path(sh("xcrun", "simctl", "get_app_container", self.device, BUNDLE, "data"))


def sh(*command, check=True, log=None, timeout=None, env=None):
    """Run a command; return stdout, or write stdout and stderr to `log`."""
    if log:
        with open(log, "a") as out:
            result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT, timeout=timeout, env=env)
        output = ""
    else:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, env=env)
        output = result.stdout.strip()
    if check and result.returncode:
        detail = f" (see {log})" if log else f": {result.stderr.strip()[-800:]}"
        raise Failed(f"`{' '.join(map(str, command[:4]))} …` exited {result.returncode}{detail}")
    return output if not log else result.returncode


def privacy(run, action, *services):
    for service in services:
        sh("xcrun", "simctl", "privacy", run.device, action, service, BUNDLE)


# MARK: - External checks: app files, settings and the Simulator's Photos rows


def clear_fixture_recordings(run):
    for leftover in (run.container() / "tmp").glob(FIXTURE_RECORDINGS):
        leftover.unlink()


def assert_no_fixture_recordings(run):
    leftovers = sorted(p.name for p in (run.container() / "tmp").glob(FIXTURE_RECORDINGS))
    assert not leftovers, f"Recordings were not removed after Trim: {leftovers}"
    return "no temporary recordings left in tmp"


def library(run):
    root = run.container()
    swings = json.loads((root / "Documents/swing_library.json").read_text())
    return root, swings, root / "Library/Application Support/SwingVideos"


def check_deletion(run):
    _, swings, videos = library(run)
    assert len(swings) == 3 and all(s["isReference"] for s in swings), swings
    files = {p.name for p in videos.iterdir()}
    assert files == {s["localVideoFilename"] for s in swings}, files
    return "only the 3 references remain on disk, with exactly their video files"


def preferences(run):
    path = run.container() / f"Library/Preferences/{BUNDLE}.plist"
    return plistlib.loads(path.read_bytes()) if path.exists() else {}


def trim_check(variant):
    """Saved clips have video and audio at the expected length; analysis got the chosen clip."""
    def check(run):
        root, swings, videos = library(run)
        prefs = preferences(run)
        ids = prefs.get("ui-testing-analysis-ids", [])
        personal = [s for s in swings if not s.get("isReference")]
        expected_clips, expected_seconds = {"export": (6, 3.0), "partial": (3, 3.0), "context": (3, 30.0)}[variant]
        assert len(personal) == expected_clips, personal
        if variant == "context":
            assert ids == [], ids
            assert prefs["capture.extraSecondsBeforeSwing"] == 0.5, prefs
            assert prefs["capture.extraSecondsAfterSwing"] == 2.25, prefs
        else:
            assert len(ids) == 1, ids
            assert any(s["id"] == ids[0] and s["localVideoFilename"] for s in personal), (ids, personal)
        for swing in personal:
            video = videos / swing["localVideoFilename"]
            assert video.is_file(), video
            probe = json.loads(sh("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(video)))
            assert {stream["codec_type"] for stream in probe["streams"]} == {"video", "audio"}, probe
            assert abs(float(probe["format"]["duration"]) - expected_seconds) < 0.15, probe
            # Fixture audio is silent; the Simulator plays it through the Mac's speakers.
            levels = subprocess.run(["ffmpeg", "-v", "info", "-i", str(video), "-af", "volumedetect", "-f", "null", "-"],
                                    capture_output=True, text=True).stderr
            peak = next(line.split("max_volume:")[1].split()[0] for line in levels.splitlines() if "max_volume:" in line)
            assert peak == "-inf" or float(peak) <= -60, f"{video.name} audio peaks at {peak} dB"
        assert_no_fixture_recordings(run)
        return f"{len(personal)} saved clips with silent audio and video, {expected_seconds:g} s each; analysis ids {ids}"
    return check


def photos_db(run):
    return Path.home() / f"Library/Developer/CoreSimulator/Devices/{run.device}/data/Media/PhotoData/Photos.sqlite"


def photos_assets(run):
    path = photos_db(run)
    if not path.exists():
        return set()
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
        return {row[0].upper() for row in db.execute("SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0")}


def grant_photos(run):
    privacy(run, "grant", "photos", "photos-add")


def storage_before(phase):
    def before(run):
        if "photos_baseline" not in run.state:
            run.state["photos_baseline"] = photos_assets(run)
            (run.artifacts / "photos-baseline.json").write_text(json.dumps(sorted(run.state["photos_baseline"])))
        privacy(run, "grant" if phase == "on" else "revoke", "photos", "photos-add")
    return before


def storage_check(phase):
    """OFF keeps every clip local with Photos denied. ON keeps the two clips saved
    locally before switching ON, and adds exactly one Photos asset per new clip."""
    def check(run):
        root, swings, videos = library(run)
        tcc = Path.home() / f"Library/Developer/CoreSimulator/Devices/{run.device}/data/Library/TCC/TCC.db"
        with sqlite3.connect(f"file:{tcc}?mode=ro", uri=True) as db:
            authorization = dict(db.execute("SELECT service, auth_value FROM access WHERE client = ?", (BUNDLE,)))
        assert authorization.get("kTCCServicePhotosAdd") == (2 if phase == "on" else 0), authorization
        personal = [s for s in swings if not s.get("isReference")]
        local = [s for s in personal if not s["photoAssetID"]]
        in_photos = [s for s in personal if s["photoAssetID"]]
        # OFF: Manual full and ranged clips stay; the Auto clip is deleted in the test.
        # ON: the same two clips, saved before switching ON, stay local.
        assert len(local) == 2, personal
        assert len(in_photos) == (3 if phase == "on" else 0), personal
        for swing in personal:
            clip = videos / swing["localVideoFilename"]
            assert clip.is_file() and clip.stat().st_size > 0, clip
        before, after = run.state["photos_baseline"], photos_assets(run)
        assert before <= after, "Verification removed a pre-existing Photos asset"
        created = after - before
        expected = {s["photoAssetID"].split("/")[0].upper() for s in in_photos}
        assert created == expected, {"unexpected": sorted(created - expected), "missing": sorted(expected - created)}
        return f"{len(local)} local-only and {len(in_photos)} Photos-backed clips; {len(created)} new Photos assets"
    return check


# MARK: - Console scan (on request)

CONSOLE_MARKERS = ["VKCImageAnalyzerRequest", "Error processing request from MAD",
                   "Visual isTranslatable", "verify_image_parameters: invalid image"]


def console_before(run):
    predicate = ('process == "SwingCoach" AND (subsystem == "com.apple.VisionKit" OR subsystem == "com.apple.Translation"'
                 ' OR subsystem == "com.apple.coregraphics" OR subsystem == "Pear.ai.SwingCoach")')
    log = open(run.artifacts / "console.log", "w")
    run.state["console"] = subprocess.Popen(
        ["xcrun", "simctl", "spawn", run.device, "log", "stream", "--level", "debug", "--style", "compact",
         "--predicate", predicate], stdout=log, stderr=subprocess.STDOUT)


def console_check(run):
    stream = run.state.pop("console")
    assert stream.poll() is None, "The console stream died; diagnostics were not observed"
    stream.terminate()
    stream.wait()
    text = (run.artifacts / "console.log").read_text(errors="replace")
    assert "SwingCoach[" in text, "No app console events captured"
    counts = {marker: text.count(marker) for marker in CONSOLE_MARKERS}
    (run.artifacts / "console-summary.json").write_text(json.dumps(counts, indent=2) + "\n")
    assert not any(counts.values()), counts
    warnings = [line for line in (run.artifacts / "build.log").read_text(errors="replace").splitlines()
                if "warning:" in line and "TrimView.swift:" in line]
    assert not warnings, warnings
    return "no frame-analysis diagnostics in the console; no TrimView compiler warnings"


# MARK: - Coach (on request, frozen legacy coaching)

COACH_PORT = 8871
COACH_VIDEO = ROOT / "SwingCoach/ReferenceSwings/DaBMIbhpel9_1.mp4"
BACKEND_PYTHON = ROOT / "backend/venv/bin/python"
POSE_MODEL = ROOT / "backend/models/pose_landmarker_heavy.task"

COACH_SEED = r'''
import json, pathlib, shutil, sys
root, video, repo = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(repo / 'backend'))
from analysis.coaching_contract import CoachingDetail, CoachingSource
from analysis.knowledge_library import KnowledgeLibrary
from analysis.coach_response_builder import intervention_text
storage = root / 'Library/Application Support/SwingVideos'
storage.mkdir(parents=True, exist_ok=True)
(root / 'Documents').mkdir(exist_ok=True)
swings = []
for i, title in [(1, 'Coaching upload fixture'), (2, 'Coaching source fixture')]:
    uid = f'00000000-0000-0000-0000-{i:012d}'
    shutil.copyfile(video, storage / f'{uid}.mp4')
    swings.append(dict(id=uid, photoAssetID='', vantage='DTL', duration=4, createdAt=100 - i,
                       analyzed=i == 2, isFavorite=False, isReference=False, title=title, localVideoFilename=f'{uid}.mp4'))
(root / 'Documents/swing_library.json').write_text(json.dumps(swings))
c = KnowledgeLibrary().cases['DcqwwGio81y-C02']
e = c['evidence'][1]
detail = CoachingDetail(status='recommend', focus='Backswing pivot · contract fixture',
    rationale='This saved fixture checks the coaching display; it is not a diagnosis of the fixture video.',
    cue=c['intervention']['cue'], reassess='Compare the intended movement and strike, then try without the prop.',
    sources=[CoachingSource(case_id=c['id'], title=c['title'], publisher=c['publisher'], url=c['source_url'],
             start_seconds=e['span_seconds'][0], end_seconds=e['span_seconds'][1], review_status=c['review_status'])],
    limitations=['Verification fixture. Live coaching model has not been called.'])
record = dict(id='10000000-0000-0000-0000-000000000002', swingID=swings[1]['id'], analysisID='source-fixture', createdAt=98,
    summary='Source-linked coaching display fixture', metrics=[],
    drills=[dict(title=c['title'], summary=intervention_text(c['intervention']))], coaching=detail.model_dump())
(root / 'Documents/analysis_library.json').write_text(json.dumps([record]))
'''


def coach_before(run):
    storage = run.artifacts / "coach-storage"
    # No model calls: neither API billing nor the Codex provider. Empty values,
    # not removed ones, so backend/.env cannot restore them through load_dotenv.
    env = {**os.environ, "OPENAI_API_KEY": "", "SWINGCOACH_COACH_PROVIDER": ""}
    log = open(run.artifacts / "coach-backend.log", "w")
    server = subprocess.Popen([str(BACKEND_PYTHON), str(ROOT / "scripts/verification/coaching_backend.py"),
                               "--storage", str(storage), "--port", str(COACH_PORT)],
                              stdout=log, stderr=subprocess.STDOUT, env=env)
    run.state["coach_server"] = server
    for _ in range(60):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{COACH_PORT}/verification-ready") as response:
                if json.load(response)["pid"] != server.pid:
                    raise Blocked(f"port {COACH_PORT} belongs to another process")
            break
        except OSError:
            if server.poll() is not None:
                raise Failed("The coaching backend exited; see coach-backend.log")
            time.sleep(0.5)
    else:
        raise Failed("The coaching backend did not start; see coach-backend.log")
    clip = run.artifacts / "coach-swing.mp4"
    sh("ffmpeg", "-v", "error", "-ss", "4", "-i", str(COACH_VIDEO), "-t", "4", "-vf", "scale=-2:640", "-an",
       "-c:v", "libx264", "-pix_fmt", "yuv420p", str(clip))
    sh(str(BACKEND_PYTHON), "-c", COACH_SEED, str(run.container()), str(clip), str(ROOT))


def coach_check(run):
    inputs = [json.loads(p.read_text()) for p in (run.artifacts / "coach-storage").rglob("input_meta.json")]
    assert inputs, "Missing persisted analysis input"
    assert any(m.get("student_goal") == "Improve contact" and m.get("golfer_context", {}).get("club") == "7 iron"
               for m in inputs), inputs
    shutil.copy(run.container() / "Documents/analysis_library.json", run.artifacts / "coach-saved-analysis.json")
    return "upload, analysis, overlays and source notes persisted with the practice context"


# MARK: - Areas

AREAS = {
    "smoke": [Step("smoke", [f"{UI}/SmokeUITests"])],
    "unit": [Step("unit", [UNIT], plan="Unit")],
    "library": [
        Step("library", [f"{UI}/LibrarySessionsUITests", f"{UI}/LibraryCollectionUITests",
                         f"{UI}/LibraryPagingUITests", f"{UNIT}/SwingSessionTests"],
             before=lambda run: privacy(run, "grant", "photos")),
        Step("library-deletion", [f"{UI}/LibraryDeletionUITests"],
             after=check_deletion, check_on=f"{UI}/LibraryDeletionUITests"),
    ],
    "review": [Step("review", [f"{UI}/FastSwipePagingUITests", f"{UI}/ReviewLockUITests",
                               f"{UI}/ReviewAnnotationUITests", f"{UNIT}/SwingReviewTests"])],
    "capture": [Step("capture", [f"{UI}/CaptureControlsUITests", f"{UI}/CaptureAudioUITests",
                                 f"{UI}/ManualTrimCancelUITests", f"{UI}/AutoReviewAnnotationUITests",
                                 f"{UNIT}/CaptureRecordingAudioSessionTests", f"{UNIT}/CaptureDiagnosticsExportTests",
                                 f"{UNIT}/InterfaceOrientationPolicyTests"],
                     before=grant_photos, after=assert_no_fixture_recordings, check_on=f"{UI}/ManualTrimCancelUITests")],
    "trim": [
        Step("trim-export", [f"{UI}/TrimReviewUITests/testManualTrimSelectionReviewExportOnlyThenSubsetAnalysis",
                             f"{UNIT}/TrimClipPreparationTests"],
             before=grant_photos, after=trim_check("export"),
             check_on=f"{UI}/TrimReviewUITests/testManualTrimSelectionReviewExportOnlyThenSubsetAnalysis"),
        Step("trim-partial-save", [f"{UI}/TrimReviewUITests/testPartialSaveKeepsFailedClipReachableForRetry"],
             before=grant_photos, after=trim_check("partial"),
             check_on=f"{UI}/TrimReviewUITests/testPartialSaveKeepsFailedClipReachableForRetry"),
        Step("trim-context", [f"{UI}/TrimReviewUITests/testContextSettingsPersistAndTrimClockMatchesPlayback",
                              f"{UNIT}/SwingClipContextTests", f"{UNIT}/AutoCaptureReviewSessionTests"],
             before=grant_photos, after=trim_check("context"),
             check_on=f"{UI}/TrimReviewUITests/testContextSettingsPersistAndTrimClockMatchesPlayback"),
    ],
    "storage": [
        Step("storage-off", [f"{UI}/SavePhotosUITests/testOffPersistsAndSavesManualTrimAndAutoLocally",
                             f"{UNIT}/ClipStorageTests"],
             before=storage_before("off"), after=storage_check("off"),
             check_on=f"{UI}/SavePhotosUITests/testOffPersistsAndSavesManualTrimAndAutoLocally"),
        Step("storage-on", [f"{UI}/SavePhotosUITests/testOnCreatesPhotosCopiesForManualTrimAndAuto"],
             before=storage_before("on"), after=storage_check("on"),
             check_on=f"{UI}/SavePhotosUITests/testOnCreatesPhotosCopiesForManualTrimAndAuto"),
    ],
    "stress": [Step("stress", [f"{UI}/FastSwipeStressUITests"], plan="OnRequest")],
    "console": [Step("console", [f"{UI}/LibraryPagingUITests"], before=console_before, after=console_check,
                     check_on=f"{UI}/LibraryPagingUITests")],
    "coach": [Step("coach", [f"{UI}/CoachingPipelineUITests", f"{UNIT}/CoachingContractTests"], plan="OnRequest",
                   before=coach_before, after=coach_check, check_on=f"{UI}/CoachingPipelineUITests")],
}
DEFAULT_AREAS = ["smoke", "unit", "library", "review", "capture", "trim", "storage"]
MAC_ONLY_AREAS = {"trim-clock"}


def within(selector, scope):
    return selector == scope or selector.startswith(scope + "/")


def only_selector(only):
    target = UI if only.split("/")[0].endswith("UITests") else UNIT
    return f"{target}/{only}"


def narrowed(step, only):
    """The step's selectors intersected with the --only selectors, or None when they do not overlap."""
    if not only:
        return step.tests
    tests = []
    for selector in step.tests:
        for wanted in only:
            if within(selector, wanted):
                tests.append(selector)
            elif within(wanted, selector):
                tests.append(wanted)
    return list(dict.fromkeys(tests)) or None


# MARK: - Running


def executed_tests(result):
    tree = json.loads(sh("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result)))
    cases = []

    def walk(node, bundle=None, suite=None):
        kind = node.get("nodeType")
        if kind in ("Unit test bundle", "UI test bundle"):
            bundle = node["name"]
        elif kind == "Test Suite":
            suite = node["name"]
        elif kind == "Test Case":
            cases.append((f"{bundle}/{suite}/{node['name'].removesuffix('()')}", node.get("result")))
        for child in node.get("children", []):
            walk(child, bundle, suite)

    for node in tree["testNodes"]:
        walk(node)
    return cases


def run_step(run, step, tests):
    started = time.monotonic()
    result = run.artifacts / f"{step.name}.xcresult"
    if step.before:
        step.before(run)
    clear_fixture_recordings(run)
    log = run.artifacts / f"{step.name}.log"
    status = sh("xcodebuild", "-project", str(ROOT / "SwingCoach.xcodeproj"), "-scheme", "SwingCoach",
                "-testPlan", step.plan, "-destination", f"platform=iOS Simulator,id={run.device}",
                "-derivedDataPath", str(DERIVED_DATA), "-parallel-testing-enabled", "NO",
                "-resultBundlePath", str(result), *[f"-only-testing:{t}" for t in tests],
                "CODE_SIGNING_ALLOWED=NO", "test-without-building", check=False, log=log)
    entry = {"step": step.name, "tests": tests}
    if not result.exists():
        raise Failed(f"{step.name}: xcodebuild exited {status} without a result bundle; see {log}")
    summary = json.loads(sh("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)))
    (run.artifacts / f"{step.name}-summary.json").write_text(json.dumps(summary, indent=2))
    sh("xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
       "--output-path", str(run.artifacts / "screenshots" / step.name), check=False)
    entry.update(passed=summary["passedTests"], failed=summary["failedTests"], skipped=summary["skippedTests"])
    run.log.append(entry)
    problems = [f"{f['testIdentifierString']}: {f['failureText']}" for f in summary.get("testFailures", [])]
    if summary["skippedTests"]:
        problems.append(f"{summary['skippedTests']} skipped; every selected test must run")
    cases = executed_tests(result)
    for selector in tests:
        if not any(within(name, selector) for name, _ in cases):
            problems.append(f"{selector} matched no test")
    if problems or status or summary["failedTests"] or summary["passedTests"] != summary["totalTestCount"]:
        problems.append(f"xcodebuild exited {status}; see {log}")
        entry["seconds"] = round(time.monotonic() - started)
        raise Failed(f"{step.name}: " + "; ".join(problems))
    if step.after and any(within(t, step.check_on) for t in tests):
        try:
            entry["check"] = step.after(run)
        except AssertionError as error:
            entry["seconds"] = round(time.monotonic() - started)
            raise Failed(f"{step.name} external check: {error}")
    entry["seconds"] = round(time.monotonic() - started)


def run_trim_clock(run):
    """The legacy observer interval must reproduce the old jumps; the production one must not."""
    started = time.monotonic()
    scratch = run.artifacts / "trim-clock"
    scratch.mkdir()
    sh("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=black:size=64x64:rate=240:duration=4",
       "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(scratch / "clock.mp4"))
    sh("swiftc", str(ROOT / "SwingCoach/Models/TrimTimecode.swift"),
       str(ROOT / "scripts/verification/TrimPlaybackClockProbe.swift"), "-o", str(scratch / "probe"))
    legacy = subprocess.run([str(scratch / "probe"), str(scratch / "clock.mp4"), "--legacy-interval"],
                            capture_output=True, text=True)
    (scratch / "before.txt").write_text(legacy.stdout)
    if legacy.returncode == 0:
        raise Failed("trim-clock: the legacy interval did not reproduce the timer jumps")
    current = sh(str(scratch / "probe"), str(scratch / "clock.mp4"))
    (scratch / "after.txt").write_text(current)
    run.log.append({"step": "trim-clock", "tests": ["TrimPlaybackClockProbe"], "passed": 1, "failed": 0,
                    "skipped": 0, "seconds": round(time.monotonic() - started),
                    "check": "slow-motion playback clock advances in tenths"})


def preflight(areas):
    needs = {"xcodebuild": True, "ffprobe": "trim" in areas,
             "ffmpeg": bool({"trim", "coach", "trim-clock"} & set(areas))}
    for tool, needed in needs.items():
        if needed and not shutil.which(tool):
            raise Blocked(f"{tool} is not installed")
    if "coach" in areas:
        for path in (BACKEND_PYTHON, POSE_MODEL, COACH_VIDEO):
            if not path.exists():
                raise Blocked(f"coach needs {path.relative_to(ROOT)}; symlink it from the main checkout")


def create_simulator(run):
    name = f"SwingCoach Verify {run.artifacts.name}"
    try:
        run.device = sh("xcrun", "simctl", "create", name, DEVICE_TYPE)
    except Failed as error:
        raise Blocked(f"cannot create an iPhone 17 Simulator: {error}")
    sh("xcrun", "simctl", "boot", run.device)
    sh("xcrun", "simctl", "bootstatus", run.device, "-b", timeout=600)


def delete_simulator(run):
    if not run.device:
        return "no Simulator created"
    sh("xcrun", "simctl", "shutdown", run.device, check=False)
    sh("xcrun", "simctl", "delete", run.device, check=False)
    devices = json.loads(sh("xcrun", "simctl", "list", "devices", "--json"))["devices"]
    if any(d["udid"] == run.device for group in devices.values() for d in group):
        return f"Simulator {run.device} still exists"
    return f"Simulator {run.device} deleted"


def build(run):
    started = time.monotonic()
    status = sh("xcodebuild", "-project", str(ROOT / "SwingCoach.xcodeproj"), "-scheme", "SwingCoach",
                "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={run.device}",
                "-derivedDataPath", str(DERIVED_DATA), "CODE_SIGNING_ALLOWED=NO", "build-for-testing",
                check=False, log=run.artifacts / "build.log")
    run.state["build_seconds"] = round(time.monotonic() - started)
    if status:
        raise Failed(f"build failed; see {run.artifacts / 'build.log'}")
    sh("xcrun", "simctl", "install", run.device,
       str(DERIVED_DATA / "Build/Products/Debug-iphonesimulator/SwingCoach.app"))


def report(run, areas, verdict):
    lines = [f"{'step':<20}{'pass':>6}{'fail':>6}{'skip':>6}{'sec':>6}  check"]
    for entry in run.log:
        lines.append(f"{entry['step']:<20}{entry.get('passed', '-'):>6}{entry.get('failed', '-'):>6}"
                     f"{entry.get('skipped', '-'):>6}{entry.get('seconds', '-'):>6}  {entry.get('check', '')}")
    if "build_seconds" in run.state:
        lines.append(f"build: {run.state['build_seconds']} s")
    (run.artifacts / "report.json").write_text(json.dumps(
        {"areas": areas, "verdict": verdict, "steps": run.log, **{k: v for k, v in run.state.items()
                                                                     if k == "build_seconds"}}, indent=2))
    print("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(prog="scripts/verify.sh", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("areas", nargs="+", metavar="area")
    parser.add_argument("--only", action="append", help="run only TestClass or TestClass/testMethod within the areas; repeatable")
    parser.add_argument("--artifacts", type=Path, help="artifact directory (default .verification-artifacts/verify/<time>)")
    args = parser.parse_args()
    areas = []
    for area in args.areas:
        for name in DEFAULT_AREAS if area == "all" else [area]:
            if name not in AREAS and name not in MAC_ONLY_AREAS:
                parser.error(f"unknown area {name!r}")
            if name not in areas:
                areas.append(name)
    only = [only_selector(o) for o in args.only] if args.only else None
    plan = [(step, narrowed(step, only)) for area in areas for step in AREAS.get(area, [])]
    plan = [(step, tests) for step, tests in plan if tests]
    for wanted in only or []:
        if not any(within(t, wanted) or within(wanted, t) for _, tests in plan for t in tests):
            parser.error(f"--only {wanted.split('/', 1)[1]} is not part of {' '.join(areas)}")
    simulator_needed = bool(plan)
    if only:
        areas = [a for a in areas if a not in MAC_ONLY_AREAS]

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    artifacts = (args.artifacts or ROOT / f".verification-artifacts/verify/{stamp}-{os.getpid()}").resolve()
    artifacts.mkdir(parents=True, exist_ok=True)
    run = Run(artifacts)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    verdict = "FAIL"
    reason = ""
    started = time.monotonic()
    DERIVED_DATA.parent.mkdir(parents=True, exist_ok=True)
    lock = open(DERIVED_DATA.parent / "lock", "w")
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Blocked("another scripts/verify.sh run is using this checkout's build")
        preflight(areas)
        (artifacts / "route.txt").write_text("\n".join([
            f"areas={' '.join(areas)} only={' '.join(args.only or ['-'])}",
            sh("git", "-C", str(ROOT), "rev-parse", "HEAD"),
            sh("git", "-C", str(ROOT), "status", "--short") or "clean",
            sh("xcodebuild", "-version").replace("\n", " "),
        ]) + "\n")
        if simulator_needed:
            create_simulator(run)
            print(f"Simulator {run.device}; building…", flush=True)
            build(run)
        # A failing step does not stop the others; the verdict lists every failure.
        failures = []
        for step, tests in plan:
            print(f"Running {step.name}…", flush=True)
            try:
                run_step(run, step, tests)
            except Failed as error:
                failures.append(str(error))
                print(f"  {error}", flush=True)
        if "trim-clock" in areas:
            try:
                run_trim_clock(run)
            except Failed as error:
                failures.append(str(error))
        if failures:
            raise Failed(" | ".join(failures))
        verdict = "PASS"
    except Blocked as error:
        verdict, reason = "BLOCKED", str(error)
    except Failed as error:
        reason = str(error)
    except KeyboardInterrupt:
        reason = "interrupted"
    except SystemExit as error:
        reason = f"terminated ({error.code})"
    finally:
        server = run.state.pop("coach_server", None)
        for process in (server, run.state.pop("console", None)):
            if process and process.poll() is None:
                process.terminate()
                process.wait()
        cleanup = delete_simulator(run)
        if "still exists" in cleanup and verdict == "PASS":
            verdict, reason = "FAIL", cleanup
        (artifacts / "cleanup.txt").write_text(cleanup + "\n")
        fcntl.flock(lock, fcntl.LOCK_UN)
        report(run, areas, verdict)
        print(f"total: {round(time.monotonic() - started)} s; {cleanup}")
        print(f"{verdict}{' ' + reason if reason else ''}")
        print(f"Artifacts: {artifacts}")
    sys.exit({"PASS": 0, "FAIL": 1, "BLOCKED": 3}[verdict])


if __name__ == "__main__":
    main()
