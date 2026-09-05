import Foundation
import CoreML
import CoreGraphics

@main
struct TensorDecodeProbe {
    static func main() throws {
        let model = URL(fileURLWithPath: CommandLine.arguments[1])
        let baseline = try BaselineGolfObjectDetector(modelURL: model, computeUnits: .cpuOnly)
        let current = try GolfObjectDetector(modelURL: model, computeUnits: .cpuOnly)
        let size = CGSize(width: 1920, height: 1080)
        func normalized(_ results: [GolfObjectDetection]) -> [[Double]] {
            results.map { [Double($0.objectClass.rawValue), $0.confidence, $0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height] }
                .sorted { $0.lexicographicallyPrecedes($1) }
        }
        func time(_ action: () -> [GolfObjectDetection]) -> Double {
            let started = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<10 { _ = action() }
            return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000 / 10
        }
        var rows: [[String: Any]] = []
        for type in [MLMultiArrayDataType.float16, .float32, .double, .int32] {
            for padded in [false, true] {
                let count = 18_900
                let tensor: MLMultiArray
                if padded {
                    let channelStride = count * 2 + 8
                    let bytesPerValue = type == .float16 ? 2 : (type == .double ? 8 : 4)
                    let byteCount = channelStride * 7 * bytesPerValue
                    let pointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
                    pointer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
                    tensor = try MLMultiArray(dataPointer: pointer, shape: [1, 7, NSNumber(value: count)], dataType: type,
                                             strides: [NSNumber(value: channelStride * 7), NSNumber(value: channelStride), 2],
                                             deallocator: { $0.deallocate() })
                } else {
                    tensor = try MLMultiArray(shape: [1, 7, NSNumber(value: count)], dataType: type)
                    for index in 0..<tensor.count { tensor[index] = 0 }
                }
                for index in stride(from: 0, to: count, by: 137) {
                    let values: [Double] = [Double(100 + index % 700), Double(230 + index % 400), 30, 20,
                                            index % 3 == 0 ? 1 : 0, index % 3 == 1 ? 1 : 0, index % 3 == 2 ? 1 : 0]
                    for channel in 0..<7 {
                        tensor[[0, NSNumber(value: channel), NSNumber(value: index)]] = NSNumber(value: values[channel])
                    }
                }
                let expected = normalized(baseline.profileDecode(tensor, size: size))
                let actual = normalized(current.profileDecode(tensor, size: size))
                guard !expected.isEmpty, expected == actual else { fatalError("Decoder results differ") }
                var before: [Double] = [], after: [Double] = []
                for _ in 0..<5 {
                    before.append(time { baseline.profileDecode(tensor, size: size) })
                    after.append(time { current.profileDecode(tensor, size: size) })
                }
                let oldMedian = before.sorted()[2], newMedian = after.sorted()[2]
                rows.append(["dataType": type.rawValue, "padded": padded, "predictionCount": count,
                             "resultsIdentical": true, "detections": actual.count,
                             "beforeMS": oldMedian, "afterMS": newMedian, "speedup": oldMedian / newMedian])
            }
        }
        let invalid = try MLMultiArray(shape: [7, 64], dataType: .float32)
        precondition(baseline.profileDecode(invalid, size: size).isEmpty && current.profileDecode(invalid, size: size).isEmpty)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["passed": true, "rows": rows], options: [.prettyPrinted, .sortedKeys]))
    }
}
