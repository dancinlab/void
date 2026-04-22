//
//  VoidCustomConfigCase.swift
//  Void
//
//  Created by luca on 16.10.2025.
//

import XCTest

class VoidCustomConfigCase: XCTestCase {
    /// We only want run these UI tests
    /// when testing manually with Xcode IDE
    ///
    /// So that we don't have to wait for each ci check
    /// to run these tedious tests
    override class var defaultTestSuite: XCTestSuite {
        // https://lldb.llvm.org/cpp_reference/PlatformDarwin_8cpp_source.html#:~:text==%20%22-,IDE_DISABLED_OS_ACTIVITY_DT_MODE

        if ProcessInfo.processInfo.environment["IDE_DISABLED_OS_ACTIVITY_DT_MODE"] != nil {
            return XCTestSuite(forTestCaseClass: Self.self)
        } else {
            return XCTestSuite(name: "Skipping \(className())")
        }
    }

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    static let defaultsSuiteName: String = "VOID_UI_TESTS"

    var configFile: URL?
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let configFile {
            try FileManager.default.removeItem(at: configFile)
        }
    }

    func updateConfig(_ newConfig: String) throws {
        if configFile == nil {
            let temporaryConfig = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("void")
            configFile = temporaryConfig
        }
        try newConfig.write(to: configFile!, atomically: true, encoding: .utf8)
    }

    func voidApplication(defaultsSuite: String = VoidCustomConfigCase.defaultsSuiteName) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        guard let configFile else {
            return app
        }
        app.launchEnvironment["VOID_CONFIG_PATH"] = configFile.path
        app.launchEnvironment["VOID_USER_DEFAULTS_SUITE"] = defaultsSuite
        return app
    }
}
