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

    func testLoadedEvidencePlanRunsXCTestStepsInOrderAndReturnsCaptures() throws {
        let outputDirectory = temporaryDirectory()
        let planURL = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "runner": "xctest",
          "launch": {
            "arguments": ["--evidence-mode"],
            "environment": { "EXAMPLE_EVIDENCE_MODE": "1" }
          },
          "steps": [
            { "name": "launch app", "kind": "launch", "phase": "before" },
            {
              "name": "wait for home",
              "kind": "wait",
              "phase": "before",
              "target": { "staticText": "Home" },
              "timeout_seconds": 12
            },
            {
              "name": "wait for search button",
              "kind": "wait",
              "phase": "before",
              "target": { "button": "Search" }
            },
            {
              "name": "capture home",
              "kind": "screenshot",
              "phase": "before",
              "path": "home.png"
            },
            {
              "name": "open search",
              "kind": "tap",
              "phase": "before",
              "target": { "button": "Search" }
            },
            {
              "name": "wait for search",
              "kind": "wait",
              "phase": "before",
              "target": { "predicate": "label == 'Search Ready'" }
            },
            {
              "name": "enter query",
              "kind": "typeText",
              "phase": "before",
              "target": { "textField": "Search Field" },
              "text": "hinge"
            },
            {
              "name": "open deep link",
              "kind": "openURL",
              "phase": "before",
              "url": "exampleapp://evidence/home"
            },
            {
              "name": "swipe results",
              "kind": "swipe",
              "phase": "before",
              "direction": "up"
            },
            {
              "name": "capture search",
              "kind": "screenshot",
              "phase": "before",
              "path": "search.png"
            }
          ]
        }
        """)
        let app = MockApplication()
        app.staticTexts = ["Home"]
        app.buttons = ["Search"]
        app.predicates = ["label == \"Search Ready\""]
        app.textFields = ["Search Field"]

        let captures = try EvidencePlanRunner.run(
            planPath: planURL.path,
            on: app,
            environment: [
                "EVIDENCE_OUTPUT_DIR": outputDirectory.path,
                "EVIDENCE_REVISION_ROLE": "before"
            ]
        )

        XCTAssertEqual(app.launchArguments, ["--evidence-mode"])
        XCTAssertEqual(app.launchEnvironment, ["EXAMPLE_EVIDENCE_MODE": "1"])
        XCTAssertEqual(app.events, [
            .launched,
            .waitedForStaticText("Home"),
            .waitedForButton("Search"),
            .capturedScreenshot,
            .tappedElement("Search"),
            .waitedForPredicate("label == \"Search Ready\""),
            .typedText("hinge", into: "Search Field"),
            .openedURL("exampleapp://evidence/home"),
            .swiped(.up),
            .capturedScreenshot
        ])
        XCTAssertEqual(captures.map(\.stepName), ["capture home", "capture search"])
        XCTAssertEqual(captures.map(\.revisionRole), ["before", "before"])
        XCTAssertEqual(
            captures.map { $0.url.path.replacingOccurrences(of: outputDirectory.path + "/", with: "") },
            ["before/home.png", "before/search.png"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: captures[0].url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: captures[1].url.path))
    }

    func testEvidencePlanFiltersPhaseStepsAndDoesNotDuplicateRevisionDirectory() throws {
        let outputDirectory = temporaryDirectory()
        let planURL = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "runner": "xctest",
          "steps": [
            { "name": "launch before", "kind": "launch", "phase": "before" },
            {
              "name": "wait before home",
              "kind": "wait",
              "phase": "before",
              "target": { "staticText": "Before Home" }
            },
            {
              "name": "capture before home",
              "kind": "screenshot",
              "phase": "before",
              "path": "before/home.png"
            },
            { "name": "launch after", "kind": "launch", "phase": "after" },
            {
              "name": "capture after home",
              "kind": "screenshot",
              "phase": "after",
              "path": "after/home.png"
            }
          ]
        }
        """)
        let app = MockApplication()
        app.staticTexts = ["Before Home"]

        let captures = try EvidencePlanRunner.run(
            planPath: planURL.path,
            on: app,
            environment: [
                "EVIDENCE_OUTPUT_DIR": outputDirectory.path,
                "EVIDENCE_REVISION_ROLE": "before"
            ]
        )

        XCTAssertEqual(app.events, [
            .launched,
            .waitedForStaticText("Before Home"),
            .capturedScreenshot
        ])
        XCTAssertEqual(captures.map(\.url.lastPathComponent), ["home.png"])
        XCTAssertEqual(
            captures[0].url.path.replacingOccurrences(of: outputDirectory.path + "/", with: ""),
            "before/home.png"
        )
    }

    func testEvidencePlanUnsupportedStepKindNamesTheStepAndReason() throws {
        let planURL = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "runner": "xctest",
          "steps": [
            { "name": "pinch image", "kind": "pinch" }
          ]
        }
        """)

        XCTAssertThrowsError(try EvidencePlanRunner.run(planPath: planURL.path, on: MockApplication())) { error in
            XCTAssertEqual(
                error as? EvidenceError,
                .unsupportedPlanStep(
                    step: "pinch image",
                    kind: "pinch",
                    reason: "XCTest runner does not support this step kind."
                )
            )
        }
    }

    func testEvidencePlanRunnerSkipsVideoStepsHandledByCLIOrchestration() throws {
        let outputDirectory = temporaryDirectory()
        let planURL = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "runner": "xctest",
          "steps": [
            { "name": "launch", "kind": "launch" },
            { "name": "start video", "kind": "startVideo", "path": "flow.mov" },
            { "name": "capture home", "kind": "screenshot", "path": "home.png" },
            { "name": "stop video", "kind": "stopVideo", "path": "flow.mov" }
          ]
        }
        """)
        let app = MockApplication()

        let captures = try EvidencePlanRunner.run(
            planPath: planURL.path,
            on: app,
            environment: ["EVIDENCE_OUTPUT_DIR": outputDirectory.path]
        )

        XCTAssertEqual(app.events, [.launched, .capturedScreenshot])
        XCTAssertEqual(captures.map(\.stepName), ["capture home"])
    }

    func testEvidencePlanRunsFromEnvironmentPlanPath() throws {
        let outputDirectory = temporaryDirectory()
        let planURL = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "runner": "xctest",
          "steps": [
            { "name": "launch", "kind": "launch" },
            { "name": "capture fallback name", "kind": "screenshot" }
          ]
        }
        """)

        let captures = try EvidencePlanRunner.runFromEnvironment(
            on: MockApplication(),
            environment: [
                "EVIDENCE_PLAN_PATH": planURL.path,
                "EVIDENCE_OUTPUT_DIR": outputDirectory.path
            ]
        )

        XCTAssertEqual(captures.map(\.url.lastPathComponent), ["capture-fallback-name.png"])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func writePlan(_ json: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("plan.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private final class MockApplication: EvidenceApplication {
    enum Event: Equatable {
        case launched
        case waitedForStaticText(String)
        case waitedForButton(String)
        case waitedForPredicate(String)
        case tappedButton(String)
        case tappedElement(String)
        case typedText(String, into: String)
        case openedURL(String)
        case swipedLeft
        case swiped(NavigationAction.SwipeDirection)
        case capturedScreenshot
    }

    var launchArguments: [String] = []
    var launchEnvironment: [String: String] = [:]
    var staticTexts: Set<String> = []
    var buttons: Set<String> = []
    var accessibilityLabels: Set<String> = []
    var textFields: Set<String> = []
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

    func tapElement(_ label: String) throws {
        guard buttons.contains(label) || accessibilityLabels.contains(label) || textFields.contains(label) else {
            throw EvidenceError.navigationFailed("Element '\(label)' was not found.")
        }
        events.append(.tappedElement(label))
    }

    func typeText(_ text: String, intoElement label: String) throws {
        guard textFields.contains(label) || accessibilityLabels.contains(label) else {
            throw EvidenceError.navigationFailed("Text input '\(label)' was not found.")
        }
        events.append(.typedText(text, into: label))
    }

    func openURL(_ url: URL) throws {
        events.append(.openedURL(url.absoluteString))
    }

    func swipeLeft() {
        events.append(.swipedLeft)
    }

    func swipe(_ direction: NavigationAction.SwipeDirection) {
        events.append(.swiped(direction))
    }

    func captureScreenshot() throws -> EvidenceScreenshot {
        events.append(.capturedScreenshot)
        return EvidenceScreenshot(pngData: Data("png".utf8))
    }
}
