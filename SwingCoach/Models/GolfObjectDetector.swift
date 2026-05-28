//
//  GolfObjectDetector.swift
//  SwingCoach
//
//  Created by Codex on 28/05/2026.
//

import AVFoundation
import CoreGraphics
import CoreML
import Vision

enum GolfObjectClass: Int, CaseIterable {
    case clubShaft = 0
    case clubhead = 1
    case golfBallCandidate = 2

    var name: String {
        switch self {
        case .clubShaft:
            return "club_shaft"
        case .clubhead:
            return "clubhead"
        case .golfBallCandidate:
            return "golf_ball_candidate"
        }
    }
}

struct GolfObjectDetection {
    let objectClass: GolfObjectClass
    let confidence: Double
    let rect: CGRect

    var center: CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }
}

final class GolfObjectDetector {
    enum DetectorError: Error {
        case modelNotFound
        case invalidOutput
    }

    private let request: VNCoreMLRequest
    private let inputSize = 960.0
    private let confidenceThreshold = 0.25
    private let iouThreshold = 0.70

    init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let modelURL: URL
        if let compiledURL = Bundle.main.url(forResource: "SwingObjectsYOLO11n", withExtension: "mlmodelc") {
            modelURL = compiledURL
        } else if let packageURL = Bundle.main.url(forResource: "SwingObjectsYOLO11n", withExtension: "mlpackage") {
            modelURL = try MLModel.compileModel(at: packageURL)
        } else {
            throw DetectorError.modelNotFound
        }

        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let visionModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        self.request = request
    }

    func detect(
        in sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        orientedImageSize: CGSize
    ) throws -> [GolfObjectDetection] {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
              let output = observation.featureValue.multiArrayValue
        else {
            throw DetectorError.invalidOutput
        }

        return decode(output: output, orientedImageSize: orientedImageSize)
    }

    private func decode(output: MLMultiArray, orientedImageSize: CGSize) -> [GolfObjectDetection] {
        guard output.shape.count == 3,
              output.shape[1].intValue >= 7
        else {
            return []
        }

        let predictionCount = output.shape[2].intValue
        var candidatesByClass: [GolfObjectClass: [GolfObjectDetection]] = [:]

        for index in 0..<predictionCount {
            var bestClass: GolfObjectClass?
            var bestConfidence = 0.0

            for objectClass in GolfObjectClass.allCases {
                let confidence = value(output, channel: 4 + objectClass.rawValue, index: index)
                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestClass = objectClass
                }
            }

            guard let bestClass, bestConfidence >= confidenceThreshold else {
                continue
            }

            let centerX = value(output, channel: 0, index: index)
            let centerY = value(output, channel: 1, index: index)
            let width = value(output, channel: 2, index: index)
            let height = value(output, channel: 3, index: index)
            let modelRect = CGRect(
                x: centerX - width / 2,
                y: centerY - height / 2,
                width: width,
                height: height
            )
            let rect = sourceRect(fromModelRect: modelRect, orientedImageSize: orientedImageSize)
            guard rect.width > 0, rect.height > 0 else { continue }

            candidatesByClass[bestClass, default: []].append(
                GolfObjectDetection(
                    objectClass: bestClass,
                    confidence: bestConfidence,
                    rect: rect
                )
            )
        }

        return candidatesByClass
            .flatMap { objectClass, detections in
                nonMaximumSuppression(detections, limit: objectClass == .golfBallCandidate ? 12 : 8)
            }
    }

    private func value(_ output: MLMultiArray, channel: Int, index: Int) -> Double {
        let strides = output.strides.map(\.intValue)
        let offset = channel * strides[1] + index * strides[2]

        switch output.dataType {
        case .float16:
            let pointer = output.dataPointer.bindMemory(to: UInt16.self, capacity: output.count)
            return Double(Float16(bitPattern: pointer[offset]))
        case .float32:
            let pointer = output.dataPointer.bindMemory(to: Float.self, capacity: output.count)
            return Double(pointer[offset])
        case .double:
            let pointer = output.dataPointer.bindMemory(to: Double.self, capacity: output.count)
            return pointer[offset]
        default:
            return output[[NSNumber(value: 0), NSNumber(value: channel), NSNumber(value: index)]].doubleValue
        }
    }

    private func sourceRect(fromModelRect modelRect: CGRect, orientedImageSize: CGSize) -> CGRect {
        guard orientedImageSize.width > 0, orientedImageSize.height > 0 else {
            return .null
        }

        let inputSize = CGFloat(self.inputSize)
        let scale = min(inputSize / orientedImageSize.width, inputSize / orientedImageSize.height)
        let scaledWidth = orientedImageSize.width * scale
        let scaledHeight = orientedImageSize.height * scale
        let padX = (inputSize - scaledWidth) / 2
        let padY = (inputSize - scaledHeight) / 2

        let x = (modelRect.minX - padX) / scale / orientedImageSize.width
        let y = (modelRect.minY - padY) / scale / orientedImageSize.height
        let width = modelRect.width / scale / orientedImageSize.width
        let height = modelRect.height / scale / orientedImageSize.height

        let rect = CGRect(x: x, y: y, width: width, height: height)
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func nonMaximumSuppression(_ detections: [GolfObjectDetection], limit: Int) -> [GolfObjectDetection] {
        var sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [GolfObjectDetection] = []

        while let detection = sorted.first, kept.count < limit {
            kept.append(detection)
            sorted.removeFirst()
            sorted.removeAll { intersectionOverUnion(detection.rect, $0.rect) >= iouThreshold }
        }

        return kept
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }

        return Double(intersectionArea / unionArea)
    }
}
