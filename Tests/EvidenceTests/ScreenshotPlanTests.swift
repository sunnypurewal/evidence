import Foundation
@testable import Evidence
import XCTest

final class ScreenshotPlanTests: XCTestCase {
    func testPlanCapturesScenesInOrderAndRunsNavigation() throws {
        let outputDirectory = temporaryDirectory()
        let app = MockApplication()
        app.staticTexts = ["Welcome", "Details"]
        app.buttons = ["Next"]

        let plan = ScreenshotPlan(
            name: "Onboarding",
            launchHook: LaunchHook(
                launchArguments: ["--ui-testing"],
                launchEnvironment: ["EVIDENCE_MODE": "1"]
            ),
            scenes: [
                ScreenshotPlan.Scene(
                    name: "Welcome",
                    anchors: [.staticText("Welcome")],
                    navigation: [.tap(label: "Next")]
                ),
                ScreenshotPlan.Scene(
                    name: "Details",
                    anchors: [.staticText("Details")],
                    navigation: [.swipeLeft]
                )
            ],
            outputDirectory: OutputDirectory(explicitURL: outputDirectory),
            anchorTimeout: 0.1
        )

        let files = try plan.run(on: app)

        XCTAssertEqual(app.launchArguments, ["--ui-testing"])
        XCTAssertEqual(app.launchEnvironment, ["EVIDENCE_MODE": "1"])
        XCTAssertEqual(app.events, [
            .launched,
            .waitedForStaticText("Welcome"),
            .capturedScreenshot,
            .tappedButton("Next"),
            .waitedForStaticText("Details"),
            .capturedScreenshot,
            .swipedLeft
        ])
        XCTAssertEqual(files.map(\.lastPathComponent), ["welcome.png", "details.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[1].path))
    }

    func testAnchorTimeoutStopsBeforeCapture() throws {
        let app = MockApplication()
        let plan = ScreenshotPlan(
            name: "Missing Anchor",
            scenes: [
                ScreenshotPlan.Scene(
                    name: "Empty",
                    anchors: [.button("Continue")]
                )
            ],
            outputDirectory: OutputDirectory(explicitURL: temporaryDirectory()),
            anchorTimeout: 0.25
        )

        XCTAssertThrowsError(try plan.run(on: app)) { error in
            XCTAssertEqual(
                error as? EvidenceError,
                .anchorTimedOut(scene: "Empty", anchor: "button 'Continue'", timeout: 0.25)
            )
        }
        XCTAssertEqual(app.events, [.launched, .waitedForButton("Continue")])
    }

    func testOutputDirectoryPrefersExplicitThenEvidenceThenAppStoreThenFallback() {
        let explicit = URL(fileURLWithPath: "/tmp/explicit", isDirectory: true)
        let evidence = "/tmp/evidence-output"
        let appStore = "/tmp/app-store-output"
        let fallback = URL(fileURLWithPath: "/tmp/fallback", isDirectory: true)

        XCTAssertEqual(
            OutputDirectory(
                explicitURL: explicit,
                environment: ["EVIDENCE_OUTPUT_DIR": evidence, "APPSTORE_SCREENSHOT_DIR": appStore],
                fallbackURL: fallback
            ).resolvedURL,
            explicit
        )
        XCTAssertEqual(
            OutputDirectory(
                environment: ["EVIDENCE_OUTPUT_DIR": evidence, "APPSTORE_SCREENSHOT_DIR": appStore],
                fallbackURL: fallback
            ).resolvedURL.path,
            evidence
        )
        XCTAssertEqual(
            OutputDirectory(
                environment: ["APPSTORE_SCREENSHOT_DIR": appStore],
                fallbackURL: fallback
            ).resolvedURL.path,
            appStore
        )
        XCTAssertEqual(
            OutputDirectory(environment: [:], fallbackURL: fallback).resolvedURL,
            fallback
        )
    }

    func testSceneNamesAreFileSafe() {
        XCTAssertEqual(
            ScreenshotPlan.Scene(name: "1. Home / Search", anchors: []).captureName,
            "1-home-search"
        )
        XCTAssertEqual(
            ScreenshotPlan.Scene(name: "   ", anchors: []).captureName,
            "scene"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class MockApplication: EvidenceApplication {
    enum Event: Equatable {
        case launched
        case waitedForStaticText(String)
        case waitedForButton(String)
        case waitedForPredicate(String)
        case tappedButton(String)
        case swipedLeft
        case capturedScreenshot
    }

    var launchArguments: [String] = []
    var launchEnvironment: [String: String] = [:]
    var staticTexts: Set<String> = []
    var buttons: Set<String> = []
    var predicates: Set<String> = []
    var events: [Event] = []

    func launch() {
        events.append(.launched)
    }

    func waitForStaticText(_ label: String, timeout: TimeInterval) -> Bool {
        events.append(.waitedForStaticText(label))
        return staticTexts.contains(label)
    }

    func waitForButton(_ label: String, timeout: TimeInterval) -> Bool {
        events.append(.waitedForButton(label))
        return buttons.contains(label)
    }

    func waitForElement(matching predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        events.append(.waitedForPredicate(predicate.predicateFormat))
        return predicates.contains(predicate.predicateFormat)
    }

    func tapButton(_ label: String) throws {
        guard buttons.contains(label) else {
            throw EvidenceError.navigationFailed("Button '\(label)' was not found.")
        }
        events.append(.tappedButton(label))
    }

    func swipeLeft() {
        events.append(.swipedLeft)
    }

    func captureScreenshot() throws -> EvidenceScreenshot {
        events.append(.capturedScreenshot)
        return EvidenceScreenshot(pngData: Data("png".utf8))
    }
}
