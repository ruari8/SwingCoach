"""Supply deterministic camera/detector input; retain real Trim, export and Photos code."""
from pathlib import Path
import sys
root = Path(sys.argv[1])
p = root / 'CaptureView.swift'
s = p.read_text()
def replace(start, end, code):
    global s
    a, b = s.index(start), s.index(end, s.index(start))
    s = s[:a] + code + '\n\n' + s[b:]
replace('    func start() {', '    private func configureAndStartSession()', '    func start() {}')
replace('    private func requestAutoCapturePhotosAccess()', '    private func restoreIdleTimer()', '    private func requestAutoCapturePhotosAccess() {}')
replace('    func startRecording() {', '    func startAutoCapture() {', '''    func startRecording() { recordedMode = ProcessInfo.processInfo.arguments.contains("-trim-context-clock") ? .ultra : .normal }
    func stopRecording() {
        let fixture = Bundle.main.url(forResource: "trim-review-fixture", withExtension: "mp4")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trim-review-\\(UUID()).mp4")
        try! FileManager.default.copyItem(at: fixture, to: url)
        fileOutput(movieOutput, didFinishRecordingTo: url, from: [], error: nil)
    }''')
replace('    func startAutoCapture() {', '    func stopAutoCapture() {', '    func startAutoCapture() {}')
s = s.replace('let finished = self.finishLiveSwingDetection()', '''let finished: (items: [DetectedSwing], summary: LiveSwingDetectionSnapshot) = (
                    [2.0, 150.0, 300.0].map { start in
                        DetectedSwing(startTime: CMTime(seconds: start, preferredTimescale: 600),
                                      endTime: CMTime(seconds: start + 1, preferredTimescale: 600),
                                      confidence: 1, impactTime: start + 0.5, declaredAt: start + 1)
                    }, LiveSwingDetectionSnapshot(status: .swingDetected, detectedSwingCount: 3))''')
p.write_text(s)
# Record the production handoff at the backend boundary without submitting jobs.
# The resulting SavedSwing IDs are verified against persisted library records.
p = root / 'AnalyseView.swift'; s=p.read_text()
start=s.index('    private func startAnalysis(')
brace=s.index('{', start)
s=s[:brace+1]+'''
        let ids = swings.map { $0.id.uuidString }
        UserDefaults.standard.set(ids, forKey: "trim-verification-analysis-ids")
        return
''' + s[brace+1:]
p.write_text(s)
# Reset private app fixture state on each UI test launch.
p = root / 'SwingCoachApp.swift';s=p.read_text().replace('struct SwingCoachApp: App {', '''struct SwingCoachApp: App {
    init() {
        UserDefaults.standard.set(true, forKey: ExperimentalSettingKey.liveAutoSwingDetectionEnabled)
        UserDefaults.standard.removeObject(forKey: "trim-verification-analysis-ids")
        if ProcessInfo.processInfo.arguments.contains("-trim-context-reset") {
            UserDefaults.standard.removeObject(forKey: SwingClipContext.beforeKey)
            UserDefaults.standard.removeObject(forKey: SwingClipContext.afterKey)
        } else if !ProcessInfo.processInfo.arguments.contains("-trim-context-clock") {
            UserDefaults.standard.set(1.0, forKey: SwingClipContext.beforeKey)
            UserDefaults.standard.set(1.0, forKey: SwingClipContext.afterKey)
        }
    }
''',1);p.write_text(s)

# Opt-in failure at the external save boundary; the production batch handles it.
p = root / 'Models/SwingLibrary.swift'; s = p.read_text()
needle = '    static func saveVideoAndGetID(url: URL) async -> String? {'
assert needle in s
s = s.replace(needle, needle + '''
        if ProcessInfo.processInfo.arguments.contains("-trim-save-failure") {
            let attempt = UserDefaults.standard.integer(forKey: "trim-save-attempt") + 1
            UserDefaults.standard.set(attempt, forKey: "trim-save-attempt")
            if attempt == 2 { return nil }
        }
''', 1)
s = s.replace('        await withCheckedContinuation { continuation in\n            var assetID',
              '        return await withCheckedContinuation { continuation in\n            var assetID', 1)
p.write_text(s)
