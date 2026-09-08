"""Supply video/detection inputs in a scratch build; keep export and PhotoKit real."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()

def replace(start_marker, end_marker, replacement):
    global source
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    source = source[:start] + replacement + '\n\n' + source[end:]

replace('    func start() {', '    private func configureAndStartSession()', '    func start() {}')
replace('    func startRecording() {', '    func startAutoCapture() {', '''    func startRecording() { recordedMode = captureMode }

    func stopRecording() {
        let fixture = Bundle.main.url(forResource: "storage-fixture", withExtension: "mp4")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("storage-manual-\\(UUID()).mp4")
        try! FileManager.default.copyItem(at: fixture, to: url)
        DispatchQueue.main.async {
            self.lastRecordingSwingDetections = ProcessInfo.processInfo.arguments.contains("-storage-range")
                ? [DetectedSwing(startTime: .zero, endTime: CMTime(seconds: 1, preferredTimescale: 600), confidence: 1)] : []
            self.lastRecordingURL = url
        }
    }''')
replace('    func startAutoCapture() {', '    func stopAutoCapture() {', '''    func startAutoCapture() {
        guard ProcessInfo.processInfo.arguments.contains("-storage-auto"), !autoCaptureIsActive else { return }
        autoCaptureIsActive = true
        let url = Bundle.main.url(forResource: "storage-fixture", withExtension: "mp4")!
        Task {
            await exportAutoDetectedSwing(
                detection: DetectedSwing(startTime: .zero, endTime: CMTime(seconds: 1, preferredTimescale: 600), confidence: 1),
                preparedClip: AutoRollingVideoBuffer.PreparedClip(
                    segments: [.init(chunkID: UUID(), url: url, range: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)), timelineStart: .zero)],
                    sourceStartTime: 0, duration: CMTime(seconds: 1, preferredTimescale: 600)),
                recordedMode: .normal,
                reviewSessionID: autoReviewSessionID
            )
        }
    }''')
path.write_text(source)
