import Foundation
import OSLog

/// D1a — system memory pressure sensor.
///
/// Wraps a Mach memory-pressure DispatchSource. The host wires `onPressure`
/// to drive snapshot save / cache trim / new-PTY refusal in `DefenseCoordinator`.
final class PressureMonitor {
    enum Level: String {
        case warning, critical
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dancinlab.void",
        category: "Defense.Pressure"
    )

    private let queue = DispatchQueue(
        label: "com.dancinlab.void.defense.pressure",
        qos: .utility
    )

    private var source: DispatchSourceMemoryPressure?

    /// Callback into the host (set by `DefenseCoordinator` after init).
    /// Default is a no-op so the monitor is safe to start before wiring.
    var onPressure: (Level) -> Void = { _ in }

    init() {}
    init(onPressure: @escaping (Level) -> Void) {
        self.onPressure = onPressure
    }

    func start() {
        guard source == nil else { return }
        let s = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: queue
        )
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let data = s.data
            if data.contains(.critical) {
                self.logger.warning("memory pressure: critical")
                self.onPressure(.critical)
            } else if data.contains(.warning) {
                self.logger.notice("memory pressure: warning")
                self.onPressure(.warning)
            }
        }
        s.resume()
        source = s
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
