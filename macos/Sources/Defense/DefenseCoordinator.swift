import Foundation
import OSLog

/// Wires D1a (PressureMonitor) + D3 (SessionSnapshot) + D5 (CrashCapture).
/// Owned by AppDelegate; lives for the app lifetime.
final class DefenseCoordinator {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dancinlab.void",
        category: "Defense.Coordinator"
    )

    let snapshot: SessionSnapshot
    private let pressure: PressureMonitor

    /// Optional hooks the host can wire to react to pressure events.
    /// Snapshot save is automatic; these are for additional UI / cache trim.
    var onWarning: (() -> Void)?
    var onCritical: (() -> Void)?

    init(snapshotProvider: @escaping SnapshotProvider) {
        self.snapshot = SessionSnapshot(provider: snapshotProvider)
        self.pressure = PressureMonitor()
        self.pressure.onPressure = { [weak self] level in
            self?.handlePressure(level)
        }
    }

    func start() {
        // D5 first — must catch crashes that happen during D3/D1 setup too.
        CrashCapture.install()
        snapshot.ensureDirectory()

        let currentPath = snapshot.dir
            .appendingPathComponent("current.json").path
        CrashCapture.setCurrentSnapshotPath(currentPath)

        // Baseline snapshot so a crash before any user activity still produces
        // a usable bundle.
        snapshot.save(reason: .periodic, force: true)

        startPeriodicSaver()
        pressure.start()
        logger.notice("defense coordinator started")
    }

    func stopForShutdown() {
        snapshot.save(reason: .shutdown, force: true)
        pressure.stop()
        periodicTimer?.cancel()
        periodicTimer = nil
    }

    // MARK: pressure routing

    private func handlePressure(_ level: PressureMonitor.Level) {
        switch level {
        case .warning:
            snapshot.save(reason: .pressureWarn)
            onWarning?()
        case .critical:
            snapshot.save(reason: .pressureCritical, force: true)
            onCritical?()
        }
    }

    // MARK: periodic timer

    private var periodicTimer: DispatchSourceTimer?
    private let periodicInterval: TimeInterval = 30

    private func startPeriodicSaver() {
        let t = DispatchSource.makeTimerSource(
            queue: DispatchQueue(
                label: "com.dancinlab.void.defense.periodic",
                qos: .utility
            )
        )
        t.schedule(deadline: .now() + periodicInterval, repeating: periodicInterval)
        t.setEventHandler { [weak self] in
            self?.snapshot.save(reason: .periodic)
        }
        t.resume()
        periodicTimer = t
    }
}
