import SwiftUI
import UIKit

/// Observes taps and stationary holds without taking the scroll view's pan.
struct PlaybackTransportGesture: UIGestureRecognizerRepresentable {
    let onTap: () -> Void
    let onHold: () -> Void
    let onHoldEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let point = recognizer.location(in: recognizer.view?.window)
        switch recognizer.state {
        case .began:
            coordinator.reset()
            coordinator.touch = .pending(point)
            coordinator.pendingHold = Task { @MainActor [weak coordinator, weak recognizer] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let coordinator, let recognizer,
                      recognizer.state == .began || recognizer.state == .changed,
                      case .pending(let origin) = coordinator.touch else { return }
                coordinator.touch = .holding(origin)
                onHold()
            }
        case .changed:
            if let origin = coordinator.touch.origin,
               hypot(point.x - origin.x, point.y - origin.y) > 10 {
                coordinator.pendingHold?.cancel()
                if case .holding = coordinator.touch { onHoldEnd() }
                coordinator.touch = .moved
            }
        case .ended:
            switch coordinator.touch {
            case .pending: onTap()
            case .holding: onHoldEnd()
            case .idle, .moved: break
            }
            coordinator.reset()
        case .cancelled, .failed:
            if case .holding = coordinator.touch { onHoldEnd() }
            coordinator.reset()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        enum Touch {
            case idle
            case pending(CGPoint)
            case holding(CGPoint)
            case moved

            var origin: CGPoint? {
                switch self {
                case .pending(let point), .holding(let point): return point
                case .idle, .moved: return nil
                }
            }
        }

        var touch = Touch.idle
        var pendingHold: Task<Void, Never>?

        func reset() {
            pendingHold?.cancel()
            pendingHold = nil
            touch = .idle
        }

        deinit { pendingHold?.cancel() }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
