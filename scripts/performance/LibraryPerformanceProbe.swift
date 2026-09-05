import UIKit
import Foundation

@main
@MainActor
final class LibraryPerformanceProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.async { self.run() }
        return true
    }

    private func run() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var report: [String: Any] = ["passed": false, "mainThread": Thread.isMainThread]
        do {
            let library = SwingLibrary.shared
            let storage = documents.appendingPathComponent("swing_library.json")
            var rows: [[String: Any]] = []
            func seed(_ count: Int) -> [SavedSwing] {
                (0..<count).map { index in
                    SavedSwing(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                               photoAssetID: "", vantage: .dtl, duration: 4.0,
                               createdAt: Date(timeIntervalSince1970: 0),
                               notes: String(repeating: "n", count: 128), analyzed: false)
                }
            }
            func timed(_ action: () -> Void) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                action()
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }
            func stats(_ values: [Double]) -> [String: Any] {
                let sorted = values.sorted()
                return ["samplesMS": values, "medianMS": sorted[sorted.count / 2],
                        "p95MS": sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]]
            }
            for count in [100, 1_000, 5_000] {
                library.swings = seed(count)
                let selected = library.swings[count / 2]
                library.toggleFavorite(selected)
                library.toggleFavorite(selected)
                let samples = (0..<20).map { _ in timed { library.toggleFavorite(selected) } }
                let saved = try JSONDecoder().decode([SavedSwing].self, from: Data(contentsOf: storage))
                precondition(saved == library.swings && saved.count == count)
                rows.append(["operation": "toggleFavorite", "libraryCount": count, "timing": stats(samples)])

                var deleteSamples: [Double] = []
                for _ in 0..<3 {
                    library.swings = seed(count)
                    let selected = Array(library.swings.prefix(min(100, count / 2)))
                    deleteSamples.append(timed {
                        library.removeSwings(withIDs: Set(selected.map(\.id)))
                    })
                    let persisted = try JSONDecoder().decode([SavedSwing].self, from: Data(contentsOf: storage))
                    precondition(persisted == library.swings && persisted.count == count - selected.count)
                }
                rows.append(["operation": "deleteSelection", "libraryCount": count,
                             "selectedCount": min(100, count / 2), "timing": stats(deleteSamples)])
            }
            for sizeMiB in [1, 128] {
                let source = documents.appendingPathComponent("copy-fixture.mov")
                try Data(repeating: 0x6d, count: sizeMiB * 1024 * 1024).write(to: source)
                var samples: [Double] = []
                for _ in 0..<5 {
                    library.swings = seed(100)
                    var added: SavedSwing?
                    samples.append(timed {
                        added = library.addSwing(photoAssetID: "", vantage: .dtl, duration: 4,
                                                 initialThumbnail: UIImage(), localSourceURL: source)
                    })
                    let destination = library.localVideoURL(for: added!)!
                    let originalBytes = try Data(contentsOf: source)
                    let copiedBytes = try Data(contentsOf: destination)
                    precondition(originalBytes == copiedBytes)
                    library.removeSwings(withIDs: [added!.id])
                }
                rows.append(["operation": "addSwingWithLocalCopy", "inputMiB": sizeMiB, "timing": stats(samples)])
                try FileManager.default.removeItem(at: source)
            }
            // Check local-file cleanup, survivors, duplicate IDs and absent IDs.
            library.swings = seed(3)
            let localRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SwingVideos", isDirectory: true)
            for index in 0..<3 {
                let name = "sentinel-\(index).mov"
                library.swings[index].localVideoFilename = name
                try Data([UInt8(index)]).write(to: localRoot.appendingPathComponent(name))
            }
            let survivor = library.swings[2]
            let first = library.swings[0].id
            library.removeSwings(withIDs: [first, first, library.swings[1].id, UUID()])
            precondition(library.swings == [survivor])
            precondition(!FileManager.default.fileExists(atPath: localRoot.appendingPathComponent("sentinel-0.mov").path))
            precondition(!FileManager.default.fileExists(atPath: localRoot.appendingPathComponent("sentinel-1.mov").path))
            precondition(FileManager.default.fileExists(atPath: localRoot.appendingPathComponent("sentinel-2.mov").path))
            let persistedSurvivors = try JSONDecoder().decode([SavedSwing].self, from: Data(contentsOf: storage))
            precondition(persistedSurvivors == [survivor])
            library.removeSwings(withIDs: [])
            library.removeSwings(withIDs: [UUID()])
            precondition(library.swings == [survivor])
            report["deletionChecksPassed"] = true
            report["rows"] = rows
            report["passed"] = true
        } catch {
            report["error"] = String(describing: error)
        }
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: documents.appendingPathComponent("profile.json"), options: .atomic)
        } catch {
            print("Could not write profile: \(error)")
        }
        exit(report["passed"] as? Bool == true ? 0 : 1)
    }
}
