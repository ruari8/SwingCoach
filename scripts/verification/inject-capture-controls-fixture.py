"""Replace hardware boundaries in the disposable capture UI verification build."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()

def replace_function(start_marker, end_marker, replacement):
    global source
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    source = source[:start] + replacement + '\n\n' + source[end:]

# Reset once at app launch, before AppStorage views are constructed. Resetting
# in CameraSession.init would erase settings when SwiftUI recreates a tab.
app_path = path.with_name('SwingCoachApp.swift')
app = app_path.read_text()
app = app.replace('struct SwingCoachApp: App {', '''struct SwingCoachApp: App {
    init() { _ = Self.captureVerificationDefaults }

    private static let captureVerificationDefaults: Void = {
        if ProcessInfo.processInfo.arguments.contains("-capture-controls-reset") {
            UserDefaults.standard.removeObject(forKey: ExperimentalSettingKey.showCaptureModelStats)
            UserDefaults.standard.set(true, forKey: ExperimentalSettingKey.liveAutoSwingDetectionEnabled)
        }
        if ProcessInfo.processInfo.arguments.contains("-capture-controls-stats") {
            UserDefaults.standard.set(true, forKey: ExperimentalSettingKey.showCaptureModelStats)
        }
    }()
''', 1)
app_path.write_text(app)

replace_function('    func start() {', '    private func configureAndStartSession()', '    func start() {}')
replace_function('    private func requestAutoCapturePhotosAccess()', '    private func restoreIdleTimer()', '    private func requestAutoCapturePhotosAccess() {}')
replace_function('    func startRecording() {', '    func startAutoCapture() {', '''    func startRecording() {
        recordedMode = captureMode
        liveSwingDetection = captureControlsSnapshot(manual: true)
    }

    func stopRecording() {
        let fixture = Bundle.main.url(forResource: "manual-cancel-fixture", withExtension: "mp4")!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-cancel-\\(UUID().uuidString).mp4")
        try! FileManager.default.copyItem(at: fixture, to: url)
        fileOutput(movieOutput, didFinishRecordingTo: url, from: [], error: nil)
    }

    private func captureControlsSnapshot(manual: Bool) -> LiveSwingDetectionSnapshot {
        if manual && !isLiveSwingDetectionEnabled {
            return LiveSwingDetectionSnapshot(status: .disabled)
        }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-capture-controls-unavailable") {
            return LiveSwingDetectionSnapshot(status: .unavailable, primaryMessage: "Model could not load")
        }
        if args.contains("-capture-controls-waiting") { return .idle }
        return LiveSwingDetectionSnapshot(
            status: .searchingBall,
            detectedSwingCount: manual ? 2 : 3,
            processedFrameCount: 80,
            targetSampleFPS: 8,
            effectiveSampleFPS: manual ? 12.5 : 8,
            averageProcessingTimeMS: manual ? 42 : 56,
            lastProcessingTimeMS: 55
        )
    }''')
replace_function('    func startAutoCapture() {', '    func stopAutoCapture() {', '''    func startAutoCapture() {
        DispatchQueue.main.async {
            guard !self.autoCaptureIsActive else { return }
            self.autoCaptureIsActive = true
            self.autoSessionSwings = SwingLibrary.shared.swings.filter(\\.isReference)
            self.autoSavedSwingCount = self.autoSessionSwings.count
            self.liveSwingDetection = self.captureControlsSnapshot(manual: false)
            self.autoCaptureStatus = AutoCaptureStatus(
                isActive: true,
                savedSwingCount: self.autoSavedSwingCount,
                pendingSwingCount: 0,
                message: "Auto watching",
                lastErrorMessage: ProcessInfo.processInfo.arguments.contains("-capture-controls-error")
                    ? "Enable Photos add access in Settings before the range session." : nil
            )
        }
    }''')
replace_function('    func resumeAutoCaptureAfterReview() {', '    func fileOutput(', '''    func resumeAutoCaptureAfterReview() {
        liveSwingDetection = captureControlsSnapshot(manual: false)
    }''')
# Remove only the Photos mutation. Keep the real session-count/deletion updates.
source = source.replace('        try await SwingLibrary.shared.deleteSwingAndPhoto(swing)\n', '')
path.write_text(source)
