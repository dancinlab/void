import Foundation
import Darwin
import OSLog

/// D5 — last-gasp crash capture.
///
/// Installs an Obj-C uncaught-exception handler and POSIX `sigaction` for
/// SIGSEGV/SIGBUS/SIGABRT/SIGILL/SIGFPE/SIGTRAP. After dumping a crash bundle,
/// we restore the default handler and re-raise so Apple's CrashReporter still
/// gets its `.ips`.
///
/// The signal handler runs on the faulting thread with a corrupt stack — it
/// must be async-signal-safe. We therefore pre-resolve the bundle directory
/// at install time and write via raw POSIX (`mkdir`, `open`, `write`).
enum CrashCapture {
    /// `~/Library/Logs/com.dancinlab.void/crashes/`
    static var crashRoot: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return logs
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("com.dancinlab.void", isDirectory: true)
            .appendingPathComponent("crashes", isDirectory: true)
    }()

    /// Pre-baked C string of the current snapshot path. Set via
    /// `setCurrentSnapshotPath` so the signal handler can use it without any
    /// Swift runtime allocation.
    private static var currentSnapshotCString: [CChar]?

    /// Set the path to `current.json` (typically `SessionSnapshot.dir/current.json`).
    /// Safe to call from any normal code path; converts to a CChar buffer once.
    static func setCurrentSnapshotPath(_ path: String) {
        currentSnapshotCString = Array(path.utf8CString)
    }

    /// Pre-allocated C string of `crashRoot` (UTF-8, NUL-terminated). The
    /// signal handler concatenates a timestamped subdir onto it.
    private static var crashRootCString: [CChar] = []

    /// Re-entry guard. If we crash *while writing the bundle*, give up cleanly.
    private static var entered = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dancinlab.void",
        category: "Defense.Crash"
    )

    /// Call once at app launch, before any other defense layer. Idempotent.
    static func install() {
        try? FileManager.default.createDirectory(
            at: crashRoot, withIntermediateDirectories: true
        )
        crashRootCString = Array(crashRoot.path.utf8CString)

        retain(NSGetUncaughtExceptionHandler())
        NSSetUncaughtExceptionHandler { exc in
            CrashCapture.handleException(exc)
        }

        for sig in [SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP] {
            var sa = sigaction()
            sa.__sigaction_u.__sa_handler = CrashCapture.signalHandler
            sigemptyset(&sa.sa_mask)
            sa.sa_flags = SA_RESTART
            sigaction(sig, &sa, nil)
        }
        logger.notice("crash capture installed at \(crashRoot.path, privacy: .public)")
    }

    // MARK: Obj-C exception path (still on a sane stack)

    private static var previousHandler: (@convention(c) (NSException) -> Void)?
    private static func retain(_ h: (@convention(c) (NSException) -> Void)?) {
        previousHandler = h
    }

    private static func handleException(_ exc: NSException) {
        let bundle = makeBundleDirectorySwift()
        let stack = (["Reason: \(exc.name.rawValue): \(exc.reason ?? "")"]
                     + exc.callStackSymbols).joined(separator: "\n")
        if let bundle {
            try? stack.write(
                to: bundle.appendingPathComponent("stack.txt"),
                atomically: true,
                encoding: .utf8
            )
            linkSnapshotInto(bundle)
        }
        previousHandler?(exc)
    }

    // MARK: POSIX signal path (async-signal-safe — minimal Swift runtime)

    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        if CrashCapture.entered {
            signal(sig, SIG_DFL); raise(sig); return
        }
        CrashCapture.entered = true

        // Build "<crashRoot>/<unix-ts>-sig<N>" via signal-safe primitives.
        var pathBuf = [CChar](repeating: 0, count: 1024)
        crashRootCString.withUnsafeBufferPointer { rootPtr in
            snprintf(
                ptr: &pathBuf,
                length: pathBuf.count,
                "%s/%ld-sig%d",
                rootPtr.baseAddress, Int(time(nil)), sig
            )
        }
        mkdir(pathBuf, 0o700)

        // Write stack.txt via backtrace_symbols_fd (async-signal-safe on macOS).
        var stackPath = pathBuf
        appendCString(&stackPath, "/stack.txt")
        let fd = open(stackPath, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        if fd >= 0 {
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
            let n = frames.withUnsafeMutableBufferPointer {
                backtrace($0.baseAddress, Int32($0.count))
            }
            backtrace_symbols_fd(&frames, n, fd)
            close(fd)
        }

        // Hardlink current snapshot (no allocation, no buffering).
        if let snap = CrashCapture.currentSnapshotCString {
            var dst = pathBuf
            appendCString(&dst, "/snapshot.json")
            snap.withUnsafeBufferPointer { src in
                if let s = src.baseAddress {
                    _ = link(s, dst)
                }
            }
        }

        // Hand back to Apple CrashReporter.
        signal(sig, SIG_DFL)
        raise(sig)
    }

    // MARK: helpers

    /// Swift-side bundle dir creation (only for the Obj-C exception path,
    /// which is *not* async-signal-safe).
    private static func makeBundleDirectorySwift() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let url = crashRoot.appendingPathComponent(stamp, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
            return url
        } catch {
            return nil
        }
    }

    private static func linkSnapshotInto(_ dir: URL) {
        guard let snap = currentSnapshotCString else { return }
        let dst = dir.appendingPathComponent("snapshot.json").path
        snap.withUnsafeBufferPointer { src in
            guard let s = src.baseAddress else { return }
            dst.withCString { d in
                _ = link(s, d)
            }
        }
    }
}

// MARK: - signal-safe C helpers (no Swift heap allocation in the hot path)

@_silgen_name("snprintf")
private func snprintf_c(_ s: UnsafeMutablePointer<CChar>, _ n: Int,
                        _ format: UnsafePointer<CChar>,
                        _ a: UnsafePointer<CChar>?, _ b: Int, _ c: Int32) -> Int32

private func snprintf(ptr: UnsafeMutablePointer<CChar>, length: Int,
                      _ format: String,
                      _ a: UnsafePointer<CChar>?, _ b: Int, _ c: Int32) {
    format.withCString { f in
        _ = snprintf_c(ptr, length, f, a, b, c)
    }
}

/// Append a static ASCII suffix to a NUL-terminated CChar buffer in place.
/// Both arguments are caller-allocated; no Swift heap involved.
private func appendCString(_ buf: inout [CChar], _ suffix: StaticString) {
    var i = 0
    while i < buf.count && buf[i] != 0 { i += 1 }
    suffix.withUTF8Buffer { sp in
        var j = 0
        while j < sp.count && i < buf.count - 1 {
            buf[i] = CChar(sp[j])
            i += 1; j += 1
        }
        buf[i] = 0
    }
}
