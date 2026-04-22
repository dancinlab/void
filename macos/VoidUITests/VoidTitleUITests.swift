//
//  VoidTitleUITests.swift
//  VoidUITests
//
//  Created by luca on 13.10.2025.
//

import XCTest

final class VoidTitleUITests: VoidCustomConfigCase {
    override func setUp() async throws {
        try await super.setUp()
        try updateConfig(#"title = "VoidUITestsLaunchTests""#)
    }

    @MainActor
    func testTitle() throws {
        let app = try voidApplication()
        app.launch()

        XCTAssertEqual(app.windows.firstMatch.title, "VoidUITestsLaunchTests", "Oops, `title=` doesn't work!")
    }
}
