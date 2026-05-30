import AVFoundation
import AppKit
import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import ImageIO
import Vision

private struct FrameReport: Encodable {
    let requestedTime: Double
    let sampleTime: Double
    let detections: [DetectionReport]
}

private struct DetectionReport: Encodable {
    let className: String
    let confidence: Double
    let rect: [Double]
}

@main
struct GenerateModelDetectionContactSheet {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count >= 4 else {
                fputs("usage: generate_model_detection_contact_sheet <video> <model.mlpackage> <times-csv> <output.jpg> [json-output]\n", stderr)
                exit(2)
            }

            let videoURL = URL(fileURLWithPath: arguments[0])
            let modelURL = URL(fileURLWithPath: arguments[1])
            let times = arguments[2]
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .sorted()
            let outputURL = URL(fileURLWithPath: arguments[3])
            let jsonURL = arguments.count > 4 ? URL(fileURLWithPath: arguments[4]) : nil
            let columns = arguments.count > 5 ? max(1, Int(arguments[5]) ?? 2) : 2
            let panelWidth = arguments.count > 6 ? max(260, Double(arguments[6]) ?? 620) : 620

            guard !times.isEmpty else {
                throw ToolError.noTimes
            }

            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw ToolError.invalidVideo
            }
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ToolError.invalidVideo
            }

            let transform = try await videoTrack.load(.preferredTransform)
            let naturalSize = try await videoTrack.load(.naturalSize)
            let orientation = orientation(for: transform)
            let orientedSize = orientedSize(naturalSize: naturalSize, orientation: orientation)
            let detector = try GolfObjectDetector(modelURL: modelURL, computeUnits: .cpuAndNeuralEngine)

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ToolError.readerSetupFailed }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? ToolError.readerSetupFailed }

            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
            imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)

            var targetIndex = 0
            var panels: [NSImage] = []
            var reports: [FrameReport] = []

            while reader.status == .reading,
                  targetIndex < times.count,
                  let sampleBuffer = output.copyNextSampleBuffer() {
                let sampleTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                guard sampleTime.isFinite else { continue }
                let requestedTime = times[targetIndex]
                guard sampleTime + 0.001 >= requestedTime else { continue }

                let detections = try detector.detect(
                    in: sampleBuffer,
                    orientation: orientation,
                    orientedImageSize: orientedSize
                )
                let imageTime = CMTime(seconds: min(max(sampleTime, 0), durationSeconds), preferredTimescale: 600)
                let frameImage = try imageGenerator.copyCGImage(at: imageTime, actualTime: nil)
                panels.append(
                    drawPanel(
                        image: frameImage,
                        requestedTime: requestedTime,
                        sampleTime: sampleTime,
                        detections: detections,
                        panelWidth: CGFloat(panelWidth)
                    )
                )
                reports.append(
                    FrameReport(
                        requestedTime: requestedTime,
                        sampleTime: sampleTime,
                        detections: detections.map {
                            DetectionReport(
                                className: $0.objectClass.name,
                                confidence: $0.confidence,
                                rect: [
                                    Double($0.rect.minX),
                                    Double($0.rect.minY),
                                    Double($0.rect.maxX),
                                    Double($0.rect.maxY),
                                ]
                            )
                        }
                    )
                )
                targetIndex += 1
            }

            if reader.status == .failed {
                throw reader.error ?? ToolError.readerSetupFailed
            }
            guard !panels.isEmpty else { throw ToolError.noFrames }

            let sheet = contactSheet(images: panels, columns: min(columns, max(1, panels.count)))
            try writeJPEG(sheet, to: outputURL)

            if let jsonURL {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(reports).write(to: jsonURL)
            }
        } catch {
            fputs("contact sheet generation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func drawPanel(
        image: CGImage,
        requestedTime: Double,
        sampleTime: Double,
        detections: [GolfObjectDetection],
        panelWidth: CGFloat
    ) -> NSImage {
        let imageAspect = CGFloat(image.height) / CGFloat(max(1, image.width))
        let imageHeight = panelWidth * imageAspect
        let headerHeight: CGFloat = 44
        let panelHeight = imageHeight + headerHeight
        let panel = NSImage(size: CGSize(width: panelWidth, height: panelHeight))

        panel.lockFocus()
        defer { panel.unlockFocus() }

        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight).fill()

        let imageRect = CGRect(x: 0, y: 0, width: panelWidth, height: imageHeight)
        NSGraphicsContext.current?.cgContext.draw(image, in: imageRect)

        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.setLineWidth(3)

        for detection in detections.sorted(by: { $0.confidence > $1.confidence }) {
            let rect = CGRect(
                x: detection.rect.minX * panelWidth,
                y: imageHeight - detection.rect.maxY * imageHeight,
                width: detection.rect.width * panelWidth,
                height: detection.rect.height * imageHeight
            )
            color(for: detection.objectClass).setStroke()
            context.stroke(rect)

            let label = String(format: "%@ %.2f", detection.objectClass.name, detection.confidence)
            drawText(
                label,
                at: CGPoint(x: rect.minX + 4, y: max(2, rect.minY + 2)),
                color: color(for: detection.objectClass),
                fontSize: 12
            )
        }
        context.restoreGState()

        let ballCount = detections.filter { $0.objectClass == .golfBallCandidate }.count
        let clubheadCount = detections.filter { $0.objectClass == .clubhead }.count
        let shaftCount = detections.filter { $0.objectClass == .clubShaft }.count
        let header = String(
            format: "req %.2fs / sample %.2fs   balls %d  heads %d  shafts %d",
            requestedTime,
            sampleTime,
            ballCount,
            clubheadCount,
            shaftCount
        )
        drawText(
            header,
            at: CGPoint(x: 8, y: imageHeight + 14),
            color: .white,
            fontSize: 15
        )

        return panel
    }

    private static func contactSheet(images: [NSImage], columns: Int) -> NSImage {
        let cellWidth = images.map(\.size.width).max() ?? 1
        let cellHeight = images.map(\.size.height).max() ?? 1
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let sheet = NSImage(size: CGSize(width: cellWidth * CGFloat(columns), height: cellHeight * CGFloat(rows)))

        sheet.lockFocus()
        defer { sheet.unlockFocus() }

        NSColor.black.setFill()
        NSRect(origin: .zero, size: sheet.size).fill()

        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * cellWidth
            let y = CGFloat(rows - row - 1) * cellHeight
            image.draw(in: CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }

        return sheet
    }

    private static func writeJPEG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
        else {
            throw ToolError.imageEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try jpeg.write(to: url)
    }

    private static func drawText(_ text: String, at point: CGPoint, color: NSColor, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .backgroundColor: NSColor.black.withAlphaComponent(0.62),
        ]
        NSString(string: text).draw(at: point, withAttributes: attributes)
    }

    private static func color(for objectClass: GolfObjectClass) -> NSColor {
        switch objectClass {
        case .clubShaft:
            return NSColor.systemBlue
        case .clubhead:
            return NSColor.systemOrange
        case .golfBallCandidate:
            return NSColor.systemGreen
        }
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let epsilon = 0.001

        func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
            abs(lhs - rhs) < epsilon
        }

        if equals(transform.a, 0), equals(transform.b, 1), equals(transform.c, -1), equals(transform.d, 0) {
            return .right
        }

        if equals(transform.a, 0), equals(transform.b, -1), equals(transform.c, 1), equals(transform.d, 0) {
            return .left
        }

        if equals(transform.a, -1), equals(transform.d, -1) {
            return .down
        }

        return .up
    }

    private static func orientedSize(naturalSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        default:
            return naturalSize
        }
    }
}

private enum ToolError: Error {
    case invalidVideo
    case imageEncodingFailed
    case noFrames
    case noTimes
    case readerSetupFailed
}
