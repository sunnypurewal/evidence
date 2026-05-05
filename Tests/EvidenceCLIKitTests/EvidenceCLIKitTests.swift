import EvidenceCLIKit
import CryptoKit
import Foundation
import XCTest

final class EvidenceCLIKitTests: XCTestCase {
    func testConfigParsingRequiresNamedFields() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        simulator_udid = "SIM-123"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Missing required field 'bundle_id' in .evidence.toml.")
            )
        }
    }

    func testConfigParsingSupportsKnownTargetsAndPreviewDefaults() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        evidence_dir = "docs/proof"
        screenshot_targets = ["6.9", "5.5", "ipad-12.9"]
        preview_targets = ["app-preview"]
        device_matrix = ["iPhone 16 Pro Max", "iPad Pro 13-inch"]
        repository_raw_base_url = "https://raw.githubusercontent.com/example/app/main"
        preview_width = 886
        preview_height = 1920
        preview_fps = 30
        preview_max_duration_seconds = 28
        """)

        let config = try EvidenceConfig.parse(document)

        XCTAssertEqual(config.scheme, "Example")
        XCTAssertEqual(config.bundleID, "com.example.app")
        XCTAssertEqual(config.simulatorUDID, "SIM-123")
        XCTAssertEqual(config.evidenceDirectory, "docs/proof")
        XCTAssertEqual(config.screenshotTargets.map(\.name), ["6.9", "5.5", "ipad-12.9"])
        XCTAssertEqual(config.deviceMatrix, ["iPhone 16 Pro Max", "iPad Pro 13-inch"])
        XCTAssertEqual(config.previewDefaults, PreviewDefaults(width: 886, height: 1920, fps: 30, maxDuration: 28))
    }

    func testConfigParsingRejectsInvalidOptionalFieldTypes() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        preview_width = "wide"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'preview_width': expected integer.")
            )
        }
    }

    func testConfigParsingRejectsInvalidOptionalFieldValues() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        preview_fps = 0
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'preview_fps': expected value >= 1.")
            )
        }
    }

    func testHelpDoesNotRequireConfig() throws {
        var output: [String] = []
        let cli = EvidenceCLI(stdout: { output.append($0) }, currentDirectory: temporaryDirectory())

        try cli.execute(["record-preview", "--help"])

        XCTAssertTrue(output.joined().contains("886x1920, 30fps, <=30s"))
    }

    func testResizeBuildsImageMagickCommandForAppStoreTargets() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["resize", "--input", "raw.png", "--target", "6.9", "--output", "store.png"])

        XCTAssertEqual(runner.commands.last?.executable, "/bin/echo")
        XCTAssertEqual(
            runner.commands.last?.arguments,
            ["raw.png", "-resize", "1290x2796^", "-gravity", "center", "-extent", "1290x2796", "store.png"]
        )
    }

    func testRecordPreviewBuildsH264NoAudioCommandWithDefaults() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["record-preview", "--input", "capture.mov", "--output", "preview.mp4"])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "-y",
                "-i", "capture.mov",
                "-an",
                "-t", "30.0",
                "-vf", "scale=886:1920,fps=30",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "preview.mp4"
            ]
        )
    }

    func testRecordPreviewSupportsTrimOptions() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "record-preview",
            "--input", "capture.mov",
            "--output", "preview.mp4",
            "--trim-start", "1.5",
            "--trim-end", "12"
        ])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "-y",
                "-ss", "1.5",
                "-i", "capture.mov",
                "-an",
                "-t", "30.0",
                "-to", "12.0",
                "-vf", "scale=886:1920,fps=30",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "preview.mp4"
            ]
        )
    }

    func testCaptureEvidenceWritesConfiguredPathAndPrintsMarkdownURL() throws {
        let directory = try configuredProject(rawBaseURL: "https://raw.githubusercontent.com/example/app/main")
        let runner = RecordingRunner(createScreenshotForSimctl: true)
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) })

        try cli.execute(["capture-evidence", "--ticket", "APP-123"])

        let screenshot = directory.appendingPathComponent("docs/build-evidence/APP-123-running.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path))
        XCTAssertEqual(
            runner.commands.last?.arguments,
            ["simctl", "io", "SIM-123", "screenshot", screenshot.path]
        )
        XCTAssertEqual(
            output.last,
            "![Build evidence](https://raw.githubusercontent.com/example/app/main/docs/build-evidence/APP-123-running.png)"
        )
    }

    func testCaptureScreenshotsForwardsWorkspaceFlagToXcodebuild() throws {
        let directory = try configuredProject(extraLines: [
            "xcode_workspace = \"ios/Example.xcworkspace\"",
            "device_matrix = [\"EvidenceUITests/AppEvidenceTests\"]"
        ])
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["capture-screenshots"])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "xcodebuild",
                "test",
                "-workspace", "ios/Example.xcworkspace",
                "-scheme", "Example",
                "-destination", "platform=iOS Simulator,id=SIM-123",
                "-only-testing", "EvidenceUITests/AppEvidenceTests"
            ]
        )
    }

    func testCaptureScreenshotsForwardsProjectFlagToXcodebuild() throws {
        let directory = try configuredProject(extraLines: [
            "xcode_project = \"ios/Example.xcodeproj\""
        ])
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["capture-screenshots"])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "xcodebuild",
                "test",
                "-project", "ios/Example.xcodeproj",
                "-scheme", "Example",
                "-destination", "platform=iOS Simulator,id=SIM-123"
            ]
        )
    }

    func testCaptureScreenshotsOmitsWorkspaceFlagWhenUnconfigured() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["capture-screenshots"])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "xcodebuild",
                "test",
                "-scheme", "Example",
                "-destination", "platform=iOS Simulator,id=SIM-123"
            ]
        )
    }

    func testConfigParsingRejectsBothXcodeWorkspaceAndProject() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        xcode_workspace = "ios/Example.xcworkspace"
        xcode_project = "ios/Example.xcodeproj"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid configuration: only one of 'xcode_workspace' or 'xcode_project' may be set in .evidence.toml.")
            )
        }
    }

    func testConfigParsingReadsXcodeWorkspaceAndRejectsEmpty() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        xcode_workspace = "ios/Example.xcworkspace"
        """)

        let config = try EvidenceConfig.parse(document)
        XCTAssertEqual(config.xcodeWorkspace, "ios/Example.xcworkspace")
        XCTAssertNil(config.xcodeProject)

        let emptyDocument = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        xcode_workspace = ""
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(emptyDocument)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'xcode_workspace': value must not be empty.")
            )
        }
    }

    // MARK: - App Store Connect screenshot uploads

    func testConfigParsesAppStoreConnectTable() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"

        [app_store_connect]
        key_id = "ABC123DEFG"
        issuer_id = "00000000-0000-0000-0000-000000000000"
        p8_path = ".keys/AuthKey_ABC123DEFG.p8"
        app_id = "1234567890"
        """)

        let config = try EvidenceConfig.parse(document)

        XCTAssertEqual(
            config.appStoreConnect,
            AppStoreConnectConfig(
                keyID: "ABC123DEFG",
                issuerID: "00000000-0000-0000-0000-000000000000",
                p8Path: ".keys/AuthKey_ABC123DEFG.p8",
                appID: "1234567890"
            )
        )
    }

    func testUploadScreenshotsDryRunListsHashMatchesWithoutMutating() throws {
        let directory = try appStoreProject()
        let image = try writeAppStorePNG(in: directory, path: "docs/build-evidence/en-US/6.9/01-home.png", width: 1290, height: 2796)
        let checksum = Insecure.MD5.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let http = MockHTTPClient(responses: [
            .json(appStoreVersionsJSON(localizationID: "loc-en", locale: "en-US")),
            .json(screenshotSetsJSON(setID: "set-67", displayType: "APP_IPHONE_67", screenshotID: "shot-1", checksum: checksum))
        ])
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: RecordingRunner(), stdout: { output.append($0) }, httpClient: http)

        try cli.execute(["upload-screenshots", "--dry-run"])

        let rendered = output.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("APP_IPHONE_67"))
        XCTAssertTrue(rendered.contains("✓"))
        XCTAssertTrue(rendered.contains("skip"))
        XCTAssertTrue(rendered.contains("Dry run"))
        XCTAssertEqual(http.requests.map(\.method), ["GET", "GET"])
    }

    func testUploadScreenshotsRejectsDimensionMismatchBeforeCallingASC() throws {
        let directory = try appStoreProject()
        _ = try writeAppStorePNG(in: directory, path: "docs/build-evidence/en-US/6.9/01-home.png", width: 100, height: 100)
        let http = MockHTTPClient()
        let cli = testCLI(directory: directory, runner: RecordingRunner(), httpClient: http)

        XCTAssertThrowsError(try cli.execute(["upload-screenshots", "--dry-run"])) { error in
            guard case .usage(let message) = (error as? CLIError) else {
                return XCTFail("expected usage error, got \(error)")
            }
            XCTAssertTrue(message.contains("requires 1290x2796"))
        }
        XCTAssertEqual(http.requests.count, 0)
    }

    func testUploadScreenshotsMapsIPadElevenToAppStoreDisplayType() throws {
        XCTAssertEqual(AppStoreScreenshotDisplayType.targetMap["ipad-11"], "APP_IPAD_PRO_3GEN_11")
    }

    func testUploadScreenshotsIPadTwelveNineAndThirteenMapToDistinctDisplayTypes() throws {
        // ipad-13 has no dedicated ScreenshotDisplayType in Apple's API as of 2025;
        // it is absent from targetMap. ipad-12.9 maps to the verified APP_IPAD_PRO_3GEN_129.
        XCTAssertEqual(AppStoreScreenshotDisplayType.targetMap["ipad-12.9"], "APP_IPAD_PRO_3GEN_129")
        XCTAssertNil(AppStoreScreenshotDisplayType.targetMap["ipad-13"])
        XCTAssertNotEqual(
            AppStoreScreenshotDisplayType.targetMap["ipad-13"],
            AppStoreScreenshotDisplayType.targetMap["ipad-12.9"]
        )
    }

    func testUploadScreenshotsFiltersLocaleLayout() throws {
        let directory = try appStoreProject()
        _ = try writeAppStorePNG(in: directory, path: "docs/build-evidence/en-US/6.9/01-home.png", width: 1290, height: 2796)
        _ = try writeAppStorePNG(in: directory, path: "docs/build-evidence/fr-FR/6.9/01-accueil.png", width: 1290, height: 2796)
        let http = MockHTTPClient(responses: [
            .json(appStoreVersionsJSON(localizationID: "loc-fr", locale: "fr-FR")),
            .json(screenshotSetsJSON(setID: "set-fr", displayType: "APP_IPHONE_67"))
        ])
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: RecordingRunner(), stdout: { output.append($0) }, httpClient: http)

        try cli.execute(["upload-screenshots", "--dry-run", "--locale", "fr-FR"])

        let rendered = output.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("fr-FR"))
        XCTAssertTrue(rendered.contains("01-accueil.png"))
        XCTAssertFalse(rendered.contains("en-US"))
        XCTAssertFalse(rendered.contains("01-home.png"))
    }

    func testUploadScreenshotsPerformsReplaceWithResumableUploadOperations() throws {
        let directory = try appStoreProject()
        let image = try writeAppStorePNG(in: directory, path: "docs/build-evidence/en-US/6.9/01-home.png", width: 1290, height: 2796)
        let checksum = Insecure.MD5.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let http = MockHTTPClient(responses: [
            .json(appStoreVersionsJSON(localizationID: "loc-en", locale: "en-US")),
            .json(screenshotSetsJSON(setID: "set-67", displayType: "APP_IPHONE_67", screenshotID: "old-shot", checksum: "different")),
            .empty(statusCode: 204),
            .json(createdScreenshotJSON(id: "new-shot", uploadURL: "https://uploads.example.com/part", length: image.count)),
            .empty(statusCode: 200),
            .json(["data": ["id": "new-shot", "type": "appScreenshots"]])
        ])
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: RecordingRunner(), stdout: { output.append($0) }, httpClient: http)

        try cli.execute(["upload-screenshots"])

        XCTAssertEqual(http.requests.map(\.method), ["GET", "GET", "DELETE", "POST", "PUT", "PATCH"])
        XCTAssertEqual(http.requests[4].url.absoluteString, "https://uploads.example.com/part")
        XCTAssertEqual(http.requests[4].body, image)
        let patchBody = try XCTUnwrap(http.requests[5].body)
        let patchJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: patchBody) as? [String: Any])
        let data = try XCTUnwrap(patchJSON["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["uploaded"] as? Bool, true)
        XCTAssertEqual(attributes["sourceFileChecksum"] as? String, checksum)
        XCTAssertTrue(output.joined(separator: "\n").contains("Uploaded en-US/APP_IPHONE_67/01-home.png"))
    }

    func testUploadScreenshotsSurfacesASCAPIFailure() throws {
        let directory = try appStoreProject()
        _ = try writeAppStorePNG(in: directory, path: "docs/build-evidence/en-US/6.9/01-home.png", width: 1290, height: 2796)
        let http = MockHTTPClient(responses: [
            .failure(statusCode: 401, message: "invalid token")
        ])
        let cli = testCLI(directory: directory, runner: RecordingRunner(), httpClient: http)

        XCTAssertThrowsError(try cli.execute(["upload-screenshots", "--dry-run"])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("HTTP 401"))
            XCTAssertTrue(message.contains("invalid token"))
        }
    }

    // MARK: - xcresult bundle capture

    private static let cleanRunSummaryJSON = """
    {
      "title": "Example.xcresult",
      "startTime": 1714000000.0,
      "finishTime": 1714000045.5,
      "environmentDescription": "Example - iOS 17",
      "topInsights": [],
      "result": "Passed",
      "totalTestCount": 12,
      "passedTests": 12,
      "failedTests": 0,
      "skippedTests": 0,
      "expectedFailures": 0,
      "statistics": [],
      "devicesAndConfigurations": [],
      "testFailures": []
    }
    """

    private static let singleFailureSummaryJSON = """
    {
      "title": "Example.xcresult",
      "startTime": 1714000000.0,
      "finishTime": 1714000020.0,
      "environmentDescription": "Example - iOS 17",
      "topInsights": [],
      "result": "Failed",
      "totalTestCount": 4,
      "passedTests": 3,
      "failedTests": 1,
      "skippedTests": 0,
      "expectedFailures": 0,
      "statistics": [],
      "devicesAndConfigurations": [],
      "testFailures": [
        {
          "testName": "testCheckoutCompletesPayment",
          "targetName": "ExampleAppTests",
          "failureText": "/Users/ci/work/ExampleApp/Tests/CheckoutTests.swift:42: XCTAssertEqual failed: (\\"declined\\") is not equal to (\\"paid\\")",
          "testIdentifier": 1,
          "testIdentifierString": "ExampleAppTests/testCheckoutCompletesPayment"
        }
      ]
    }
    """

    func testXcresultSummaryParsesCleanRun() throws {
        let summary = try XcresultSummary.parse(Self.cleanRunSummaryJSON)

        XCTAssertEqual(summary.totalTestCount, 12)
        XCTAssertEqual(summary.passedTests, 12)
        XCTAssertEqual(summary.failedTests, 0)
        XCTAssertEqual(summary.failures.count, 0)
        XCTAssertEqual(summary.durationSeconds, 45.5)
        XCTAssertEqual(summary.result, "Passed")
    }

    func testXcresultSummaryParsesSingleFailureWithFileLine() throws {
        let summary = try XcresultSummary.parse(Self.singleFailureSummaryJSON)

        XCTAssertEqual(summary.failedTests, 1)
        XCTAssertEqual(summary.failures.count, 1)
        let failure = try XCTUnwrap(summary.failures.first)
        XCTAssertEqual(failure.testName, "testCheckoutCompletesPayment")
        XCTAssertEqual(failure.targetName, "ExampleAppTests")
        XCTAssertEqual(failure.fileLine, "/Users/ci/work/ExampleApp/Tests/CheckoutTests.swift:42")
    }

    func testXcresultMarkdownRendersHeadlineCountsAndFailureFileLine() throws {
        let summary = try XcresultSummary.parse(Self.singleFailureSummaryJSON)
        let markdown = XcresultMarkdown.render(summary, ticket: "APP-901")

        XCTAssertTrue(markdown.contains("# APP-901 — test summary"), "missing header: \(markdown)")
        XCTAssertTrue(markdown.contains("- Result: **Failed**"), "missing result line: \(markdown)")
        XCTAssertTrue(markdown.contains("- Total: 4"))
        XCTAssertTrue(markdown.contains("- Passed: 3"))
        XCTAssertTrue(markdown.contains("- Failed: 1"))
        XCTAssertTrue(markdown.contains("Duration: 20.00s"))
        XCTAssertTrue(markdown.contains("**testCheckoutCompletesPayment** (ExampleAppTests)"))
        XCTAssertTrue(markdown.contains("`/Users/ci/work/ExampleApp/Tests/CheckoutTests.swift:42`"))
    }

    func testCaptureEvidenceWithXcresultEnabledRunsXcodebuildAndWritesSummary() throws {
        let directory = try configuredProject(extraLines: [
            "xcresult_enabled = true"
        ])
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            fabricateXcresultBundle: true,
            xcresulttoolSummaryStdout: Self.cleanRunSummaryJSON
        )
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) })

        try cli.execute(["capture-evidence", "--ticket", "APP-200"])

        let evidenceDir = directory.appendingPathComponent("docs/build-evidence")
        let summary = evidenceDir.appendingPathComponent("APP-200-tests.md")
        let bundle = evidenceDir.appendingPathComponent("APP-200.xcresult")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.path), "summary not written")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.path), "bundle not retained when keep_full_bundle defaults true")

        let xcodebuildCommand = runner.commands.first(where: { $0.arguments.first == "xcodebuild" })
        XCTAssertNotNil(xcodebuildCommand)
        XCTAssertTrue(xcodebuildCommand?.arguments.contains("-resultBundlePath") == true)
        XCTAssertTrue(xcodebuildCommand?.arguments.contains(bundle.path) == true)

        let summarytoolCommand = runner.commands.first(where: { $0.arguments.starts(with: ["xcresulttool", "get", "test-results", "summary"]) })
        XCTAssertNotNil(summarytoolCommand)
        XCTAssertTrue(summarytoolCommand?.arguments.contains("--path") == true)
        XCTAssertTrue(summarytoolCommand?.arguments.contains(bundle.path) == true)

        let written = try String(contentsOf: summary, encoding: .utf8)
        XCTAssertTrue(written.contains("# APP-200 — test summary"))
        XCTAssertTrue(written.contains("Total: 12"))
    }

    func testCaptureEvidenceWithKeepFullBundleFalseMovesBundleToCache() throws {
        let directory = try configuredProject(extraLines: [
            "xcresult_enabled = true",
            "xcresult_keep_full_bundle = false"
        ])
        let cacheDirectory = directory.appendingPathComponent("xcresult-cache", isDirectory: true)
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            fabricateXcresultBundle: true,
            xcresulttoolSummaryStdout: Self.cleanRunSummaryJSON
        )
        let cli = testCLI(directory: directory, runner: runner, cacheDirectory: cacheDirectory)

        try cli.execute(["capture-evidence", "--ticket", "APP-300"])

        let evidenceDir = directory.appendingPathComponent("docs/build-evidence")
        let summary = evidenceDir.appendingPathComponent("APP-300-tests.md")
        let bundleInEvidence = evidenceDir.appendingPathComponent("APP-300.xcresult")
        let bundleInCache = cacheDirectory.appendingPathComponent("APP-300.xcresult")

        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.path), "summary should remain in evidence dir")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleInEvidence.path), "bundle should be moved out of evidence dir")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleInCache.path), "bundle should land in cache dir")
    }

    func testCaptureEvidenceXcresultSummaryOnlyFlagOverridesKeepFullBundle() throws {
        let directory = try configuredProject(extraLines: [
            "xcresult_enabled = true",
            "xcresult_keep_full_bundle = true"
        ])
        let cacheDirectory = directory.appendingPathComponent("xcresult-cache", isDirectory: true)
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            fabricateXcresultBundle: true,
            xcresulttoolSummaryStdout: Self.cleanRunSummaryJSON
        )
        let cli = testCLI(directory: directory, runner: runner, cacheDirectory: cacheDirectory)

        try cli.execute(["capture-evidence", "--ticket", "APP-301", "--xcresult-summary-only"])

        let bundleInEvidence = directory.appendingPathComponent("docs/build-evidence/APP-301.xcresult")
        let bundleInCache = cacheDirectory.appendingPathComponent("APP-301.xcresult")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleInEvidence.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleInCache.path))
    }

    func testCaptureEvidenceXcresultTestFailureWritesSummaryAndThrows() throws {
        let directory = try configuredProject(extraLines: [
            "xcresult_enabled = true"
        ])
        // xcodebuild test exits non-zero on test failure, but the bundle IS
        // produced — the markdown must still be written and the CLI must
        // surface the non-zero exit so CI catches the regression.
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            fabricateXcresultBundle: true,
            xcresulttoolSummaryStdout: Self.singleFailureSummaryJSON,
            xcodebuildExitCode: 65
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute(["capture-evidence", "--ticket", "APP-410"])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("1 failure"))
        }

        let summary = directory.appendingPathComponent("docs/build-evidence/APP-410-tests.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.path), "summary should be written even on failure")
        let written = try String(contentsOf: summary, encoding: .utf8)
        XCTAssertTrue(written.contains("- Result: **Failed**"))
        XCTAssertTrue(written.contains("**testCheckoutCompletesPayment**"))
    }

    func testCaptureEvidenceXcresultBuildErrorWritesFastFailMarkdownAndThrows() throws {
        let directory = try configuredProject(extraLines: [
            "xcresult_enabled = true"
        ])
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            fabricateXcresultBundle: false, // simulate build failure: no bundle produced
            xcodebuildExitCode: 65,
            xcodebuildStderr: "error: no such module 'Missing'"
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute(["capture-evidence", "--ticket", "APP-400"])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("xcodebuild test failed"))
        }

        let summary = directory.appendingPathComponent("docs/build-evidence/APP-400-tests.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.path))
        let written = try String(contentsOf: summary, encoding: .utf8)
        XCTAssertTrue(written.contains("- Result: **Build error**"))
        XCTAssertTrue(written.contains("no such module 'Missing'"))
    }

    func testCaptureEvidenceXcresultDisabledByDefaultDoesNotInvokeXcodebuild() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner(createScreenshotForSimctl: true)
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["capture-evidence", "--ticket", "APP-500"])

        XCTAssertNil(runner.commands.first(where: { $0.arguments.first == "xcodebuild" }))
        XCTAssertNil(runner.commands.first(where: { $0.arguments.starts(with: ["xcresulttool"]) }))
    }

    func testConfigParsesXcresultFlagsAndDefaults() throws {
        let baseDocument = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        """)

        let baseConfig = try EvidenceConfig.parse(baseDocument)
        XCTAssertEqual(baseConfig.xcresult, XcresultConfig(enabled: false, keepFullBundle: true))

        let configuredDocument = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        xcresult_enabled = true
        xcresult_keep_full_bundle = false
        """)

        let configured = try EvidenceConfig.parse(configuredDocument)
        XCTAssertTrue(configured.xcresult.enabled)
        XCTAssertFalse(configured.xcresult.keepFullBundle)
    }

    func testConfigRejectsNonBooleanXcresultEnabled() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        xcresult_enabled = "yes"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'xcresult_enabled': expected boolean.")
            )
        }
    }

    func testCaptureEvidenceInfersRawGitHubURLFromOriginRemote() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            gitRemote: "git@github.com:example/app.git\n"
        )
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) })

        try cli.execute(["capture-evidence", "--ticket", "APP-456"])

        XCTAssertEqual(
            output.last,
            "![Build evidence](https://raw.githubusercontent.com/example/app/main/docs/build-evidence/APP-456-running.png)"
        )
    }

    // MARK: - Platform and web config

    func testConfigDefaultsPlatformToIOS() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        """)

        let config = try EvidenceConfig.parse(document)
        XCTAssertEqual(config.platform, .ios)
        XCTAssertNil(config.webConfig)
    }

    func testConfigParsesFullValidWebConfig() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_url = "https://example.com"
        web_viewports = ["desktop-1440", "mobile-390", "1280x800"]
        web_full_page = false
        web_wait_until = "load"
        """)

        let config = try EvidenceConfig.parse(document)
        XCTAssertEqual(config.platform, .web)
        let web = try XCTUnwrap(config.webConfig)
        XCTAssertEqual(web.url, "https://example.com")
        XCTAssertEqual(web.viewports, ["desktop-1440", "mobile-390", "1280x800"])
        XCTAssertEqual(web.fullPage, false)
        XCTAssertEqual(web.waitUntil, "load")
    }

    func testWebConfigDefaultsFullPageTrueAndWaitUntilNetworkidle() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_url = "https://example.com"
        web_viewports = ["desktop-1440"]
        """)

        let config = try EvidenceConfig.parse(document)
        let web = try XCTUnwrap(config.webConfig)
        XCTAssertEqual(web.fullPage, true)
        XCTAssertEqual(web.waitUntil, "networkidle")
    }

    func testWebConfigRequiresWebURLWhenPlatformIsWeb() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_viewports = ["desktop-1440"]
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Missing required field 'web_url' when platform = \"web\" in .evidence.toml.")
            )
        }
    }

    func testWebConfigRequiresWebViewportsWhenPlatformIsWeb() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_url = "https://example.com"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Missing required field 'web_viewports' when platform = \"web\" in .evidence.toml.")
            )
        }
    }

    func testWebConfigRejectsUnknownWaitUntilValue() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_url = "https://example.com"
        web_viewports = ["desktop-1440"]
        web_wait_until = "interactive"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'web_wait_until': unknown value 'interactive'. Accepted values: networkidle, load, domcontentloaded.")
            )
        }
    }

    func testWebConfigRejectsUnknownNamedViewport() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_url = "https://example.com"
        web_viewports = ["tablet-768"]
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            guard case .config(let message) = (error as? CLIError) else {
                return XCTFail("expected config error, got \(error)")
            }
            XCTAssertTrue(message.contains("tablet-768"), "error should mention the unknown viewport: \(message)")
            XCTAssertTrue(message.contains("desktop-1440"), "error should list named presets: \(message)")
        }
    }

    func testWebConfigAcceptsCustomWxHViewport() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        platform = "web"
        web_url = "https://example.com"
        web_viewports = ["1920x1080"]
        """)

        let config = try EvidenceConfig.parse(document)
        let web = try XCTUnwrap(config.webConfig)
        XCTAssertEqual(web.viewports, ["1920x1080"])
    }

    func testConfigDoesNotParseWebConfigWhenPlatformIsIOS() throws {
        // web_* keys present but platform defaults to ios — should not throw
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        web_url = "https://example.com"
        web_viewports = ["desktop-1440"]
        """)

        let config = try EvidenceConfig.parse(document)
        XCTAssertEqual(config.platform, .ios)
        XCTAssertNil(config.webConfig)
    }

    // MARK: - capture-web

    func testResolveViewportPresets() {
        XCTAssertEqual(EvidenceCLI.resolveViewport("desktop-1440"), "1440x900")
        XCTAssertEqual(EvidenceCLI.resolveViewport("mobile-390"), "390x844")
        XCTAssertEqual(EvidenceCLI.resolveViewport("1280x800"), "1280x800")
        XCTAssertEqual(EvidenceCLI.resolveViewport("custom"), "custom")
    }

    func testPageSlugDerivation() {
        XCTAssertEqual(EvidenceCLI.pageSlug(from: "https://example.com"), "index")
        XCTAssertEqual(EvidenceCLI.pageSlug(from: "https://example.com/"), "index")
        XCTAssertEqual(EvidenceCLI.pageSlug(from: "https://example.com/about"), "about")
        XCTAssertEqual(EvidenceCLI.pageSlug(from: "https://example.com/about/team"), "about-team")
        XCTAssertEqual(EvidenceCLI.pageSlug(from: "not a url"), "index")
    }

    func testCaptureWebInvokesNodeForEachViewport() throws {
        let directory = try webProject()
        let runner = RecordingRunner(createFilesForNode: true)
        let cli = testCLI(directory: directory, runner: runner, node: "/bin/echo")

        try cli.execute(["capture-web"])

        // Filter to node (capture script) invocations only — identified by the
        // first argument ending in ".js". The git remote call also uses /bin/echo
        // in test toolPaths but should not be counted here.
        let nodeCalls = runner.commands.filter {
            $0.executable == "/bin/echo" && $0.arguments.first?.hasSuffix(".js") == true
        }
        XCTAssertEqual(nodeCalls.count, 2, "expected one node invocation per viewport")
        let firstArgs = try XCTUnwrap(nodeCalls.first?.arguments)
        let secondArgs = try XCTUnwrap(nodeCalls.last?.arguments)
        XCTAssertTrue(firstArgs.contains("1440x900"), "first call should use desktop viewport spec: \(firstArgs)")
        XCTAssertTrue(secondArgs.contains("390x844"), "second call should use mobile viewport spec: \(secondArgs)")
    }

    func testCaptureWebRejectsNonWebPlatform() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner, node: "/bin/echo")

        XCTAssertThrowsError(try cli.execute(["capture-web"])) { error in
            guard case .usage = (error as? CLIError) else {
                return XCTFail("expected usage error, got \(error)")
            }
        }
    }

    // MARK: - capture-web PR comment

    func testCaptureWebDryRunPrintsCommentBodyToStdout() throws {
        let directory = try webProject(rawBaseURL: "https://raw.githubusercontent.com/example/app/main")
        let runner = RecordingRunner(createFilesForNode: true)
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) }, node: "/bin/echo")

        try cli.execute(["capture-web"])

        // Dry-run: no --comment-on-pr flag → comment body printed to stdout
        let joined = output.joined(separator: "\n")
        XCTAssertTrue(joined.contains("## Evidence —"), "expected Evidence heading in stdout: \(joined)")
        XCTAssertTrue(joined.contains("### desktop-1440"), "expected desktop-1440 section: \(joined)")
        XCTAssertTrue(joined.contains("### mobile-390"), "expected mobile-390 section: \(joined)")
        XCTAssertTrue(joined.contains("![desktop-1440]"), "expected desktop-1440 image tag: \(joined)")
        XCTAssertTrue(joined.contains("![mobile-390]"), "expected mobile-390 image tag: \(joined)")
        XCTAssertTrue(joined.contains("Captured by evidence"), "expected footer line: \(joined)")
        XCTAssertTrue(joined.contains("raw.githubusercontent.com/example/app/"), "expected raw github URL: \(joined)")
    }

    func testCaptureWebCommentBodyContainsCorrectStructure() throws {
        // Test comment body structure: heading, two viewport sections, footer
        let directory = try webProject(rawBaseURL: "https://raw.githubusercontent.com/example/app/main")
        let runner = RecordingRunner(createFilesForNode: true)
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) }, node: "/bin/echo")

        try cli.execute(["capture-web"])

        // Filter out the "Captured X screenshot at ..." lines — isolate the comment body
        let commentLines = output.filter { !$0.hasPrefix("Captured ") }
        let commentBody = commentLines.joined(separator: "\n")

        // Heading contains ISO 8601 date (YYYY-MM-DD)
        let datePattern = #"\d{4}-\d{2}-\d{2}"#
        XCTAssertTrue(
            commentBody.range(of: datePattern, options: .regularExpression) != nil,
            "expected ISO 8601 date in heading: \(commentBody)"
        )

        // Each viewport has its own H3 section
        XCTAssertTrue(commentBody.contains("### desktop-1440"))
        XCTAssertTrue(commentBody.contains("### mobile-390"))

        // Image markdown uses raw GitHub URL (branch segment may be substituted via GITHUB_HEAD_REF)
        XCTAssertTrue(commentBody.contains("raw.githubusercontent.com/example/app/"))
        XCTAssertTrue(commentBody.contains("desktop-1440/index.png"))
        XCTAssertTrue(commentBody.contains("mobile-390/index.png"))

        // Footer
        XCTAssertTrue(commentBody.contains("Playwright"))
        XCTAssertTrue(commentBody.contains("Chromium headless"))
    }

    func testCaptureWebCommentOnPRWithoutTokenErrors() throws {
        let directory = try webProject(rawBaseURL: "https://raw.githubusercontent.com/example/app/main")
        let runner = RecordingRunner(createFilesForNode: true)
        let cli = testCLI(directory: directory, runner: runner, node: "/bin/echo")

        // Ensure GITHUB_TOKEN is not set for this test by using a custom env — we
        // cannot unset a process env in-process, so we verify the error path by
        // checking that the error message matches when the flag is set but the
        // env var is absent. We synthesise this by injecting a CLI whose
        // ProcessInfo would see no token; since we cannot control the real env
        // safely in unit tests, we instead test that passing an explicit empty
        // token flag also rejects (empty string is treated as missing).
        // The real "no env var" path is covered by the integration contract.
        XCTAssertThrowsError(
            try cli.execute(["capture-web", "--comment-on-pr", "true", "--github-token", ""])
        ) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(
                message.contains("GitHub token"),
                "error should mention GitHub token: \(message)"
            )
        }
    }

    func testExtractPRNumber() {
        XCTAssertEqual(EvidenceCLI.extractPRNumber(from: "refs/pull/42/merge"), "42")
        XCTAssertEqual(EvidenceCLI.extractPRNumber(from: "refs/pull/1/merge"), "1")
        XCTAssertEqual(EvidenceCLI.extractPRNumber(from: "refs/pull/100/merge"), "100")
        XCTAssertNil(EvidenceCLI.extractPRNumber(from: "refs/heads/main"))
        XCTAssertNil(EvidenceCLI.extractPRNumber(from: ""))
        XCTAssertNil(EvidenceCLI.extractPRNumber(from: "refs/pull/42/head"))
    }

    func testCaptureWebCLIIntegration() throws {
        let nodePath = "/usr/local/bin/node"
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: nodePath), "node not found")

        let checkProc = Process()
        checkProc.executableURL = URL(fileURLWithPath: nodePath)
        checkProc.arguments = ["-e", "require('playwright')"]
        checkProc.standardOutput = FileHandle.nullDevice
        checkProc.standardError = FileHandle.nullDevice
        try checkProc.run()
        checkProc.waitUntilExit()
        try XCTSkipIf(checkProc.terminationStatus != 0, "playwright not installed")

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let htmlFile = tmpDir.appendingPathComponent("index.html")
        try "<html><body style='height:3000px;background:blue'>hello</body></html>".write(to: htmlFile, atomically: true, encoding: .utf8)

        let port = 8765
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", "\(port)", "--directory", tmpDir.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate() }
        Thread.sleep(forTimeInterval: 1.0)

        let outDir = tmpDir.appendingPathComponent("out")
        let toml = """
        platform = "web"
        web_url = "http://localhost:\(port)"
        web_viewports = ["desktop-1440", "mobile-390"]
        web_full_page = true
        web_wait_until = "load"
        evidence_dir = "\(outDir.path)"
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        """
        try toml.write(to: tmpDir.appendingPathComponent(".evidence.toml"), atomically: true, encoding: .utf8)

        let cli = EvidenceCLI(
            runner: ProcessCommandRunner(),
            stdout: { _ in },
            currentDirectory: tmpDir,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo", node: nodePath)
        )
        try cli.execute(["capture-web"])

        let desktop = outDir.appendingPathComponent("desktop-1440/index.png")
        let mobile = outDir.appendingPathComponent("mobile-390/index.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.path), "desktop PNG not created")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mobile.path), "mobile PNG not created")

        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let desktopData = try Data(contentsOf: desktop)
        let mobileData = try Data(contentsOf: mobile)
        XCTAssertGreaterThanOrEqual(desktopData.count, 8)
        XCTAssertGreaterThanOrEqual(mobileData.count, 8)
        XCTAssertEqual(Array(desktopData.prefix(8)).map { UInt8($0) }, magic, "desktop PNG invalid")
        XCTAssertEqual(Array(mobileData.prefix(8)).map { UInt8($0) }, magic, "mobile PNG invalid")
    }

    func testCaptureWebIntegration() throws {
        let nodePath = "/usr/local/bin/node"
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: nodePath), "node not found")

        let checkProc = Process()
        checkProc.executableURL = URL(fileURLWithPath: nodePath)
        checkProc.arguments = ["-e", "require('playwright')"]
        let devNull = FileHandle.nullDevice
        checkProc.standardOutput = devNull
        checkProc.standardError = devNull
        try checkProc.run()
        checkProc.waitUntilExit()
        try XCTSkipIf(checkProc.terminationStatus != 0, "playwright not installed")

        // Locate the EvidenceCLIKit resource bundle bundled alongside the test executable.
        let testBundleURL = Bundle(for: EvidenceCLIKitTests.self).bundleURL
        let resourceBundleURL = testBundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("evidence_EvidenceCLIKit.bundle")
        let candidateBundle = Bundle(url: resourceBundleURL)
        guard let scriptURL = candidateBundle?.url(forResource: "capture-web", withExtension: "js") else {
            XCTFail("capture-web.js not in bundle"); return
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let htmlFile = tmpDir.appendingPathComponent("index.html")
        try "<html><body style='height:3000px;background:red'>hello</body></html>".write(to: htmlFile, atomically: true, encoding: .utf8)

        let port = 18765
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", "\(port)", "--directory", tmpDir.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate() }
        Thread.sleep(forTimeInterval: 1.0)

        let outputFile = tmpDir.appendingPathComponent("out.png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: nodePath)
        capture.arguments = [scriptURL.path, "http://localhost:\(port)/", "1440x900", "true", "networkidle", outputFile.path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0, "capture-web.js exited non-zero")

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), "PNG not created")
        let data = try Data(contentsOf: outputFile)
        XCTAssertGreaterThanOrEqual(data.count, 8)
        let magic: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        XCTAssertEqual(Array(data.prefix(8)).map { UInt8($0) }, magic, "Not a valid PNG file")
    }

    // MARK: helpers

    private func configuredProject(rawBaseURL: String? = nil, extraLines: [String] = []) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines = [
            "scheme = \"Example\"",
            "bundle_id = \"com.example.app\"",
            "simulator_udid = \"SIM-123\""
        ]
        if let rawBaseURL {
            lines.append("repository_raw_base_url = \"\(rawBaseURL)\"")
        }
        lines.append(contentsOf: extraLines)
        try lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent(".evidence.toml"),
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    private func appStoreProject() throws -> URL {
        let directory = try configuredProject(extraLines: [
            "",
            "[app_store_connect]",
            "key_id = \"ABC123DEFG\"",
            "issuer_id = \"00000000-0000-0000-0000-000000000000\"",
            "p8_path = \".keys/AuthKey_ABC123DEFG.p8\"",
            "app_id = \"1234567890\""
        ])
        let keyURL = directory.appendingPathComponent(".keys/AuthKey_ABC123DEFG.p8")
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try P256.Signing.PrivateKey().pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)
        return directory
    }

    @discardableResult
    private func writeAppStorePNG(in directory: URL, path: String, width: Int, height: Int) throws -> Data {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])
        data.append(contentsOf: Array("IHDR".utf8))
        func appendUInt32(_ value: Int) {
            data.append(UInt8((value >> 24) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8(value & 0xff))
        }
        appendUInt32(width)
        appendUInt32(height)
        data.append(contentsOf: [0x08, 0x02, 0x00, 0x00, 0x00])
        try data.write(to: url)
        return data
    }

    private func appStoreVersionsJSON(localizationID: String, locale: String) -> [String: Any] {
        [
            "data": [["id": "version-1", "type": "appStoreVersions"]],
            "included": [[
                "id": localizationID,
                "type": "appStoreVersionLocalizations",
                "attributes": ["locale": locale]
            ]]
        ]
    }

    private func screenshotSetsJSON(
        setID: String,
        displayType: String,
        screenshotID: String? = nil,
        checksum: String? = nil
    ) -> [String: Any] {
        var included: [[String: Any]] = []
        if let screenshotID {
            included.append([
                "id": screenshotID,
                "type": "appScreenshots",
                "attributes": [
                    "fileName": "01-home.png",
                    "sortOrder": 1,
                    "sourceFileChecksum": checksum ?? ""
                ],
                "relationships": [
                    "appScreenshotSet": [
                        "data": ["id": setID, "type": "appScreenshotSets"]
                    ]
                ]
            ])
        }
        return [
            "data": [[
                "id": setID,
                "type": "appScreenshotSets",
                "attributes": ["screenshotDisplayType": displayType]
            ]],
            "included": included
        ]
    }

    private func createdScreenshotJSON(id: String, uploadURL: String, length: Int) -> [String: Any] {
        [
            "data": [
                "id": id,
                "type": "appScreenshots",
                "attributes": [
                    "uploadOperations": [[
                        "method": "PUT",
                        "url": uploadURL,
                        "offset": 0,
                        "length": length,
                        "requestHeaders": [
                            ["name": "Content-Type", "value": "image/png"]
                        ]
                    ]]
                ]
            ]
        ]
    }

    private func webProject(rawBaseURL: String? = nil) throws -> URL {
        try configuredProject(rawBaseURL: rawBaseURL, extraLines: [
            "platform = \"web\"",
            "web_url = \"http://localhost:8765\"",
            "web_viewports = [\"desktop-1440\", \"mobile-390\"]"
        ])
    }

    private func testCLI(
        directory: URL,
        runner: RecordingRunner,
        stdout: @escaping (String) -> Void = { _ in },
        cacheDirectory: URL? = nil,
        httpClient: HTTPClient = MockHTTPClient(),
        node: String = "/usr/local/bin/node"
    ) -> EvidenceCLI {
        EvidenceCLI(
            runner: runner,
            stdout: stdout,
            currentDirectory: directory,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo", node: node),
            httpClient: httpClient,
            cacheDirectory: cacheDirectory ?? directory.appendingPathComponent("evidence-cache", isDirectory: true)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

fileprivate final class MockHTTPClient: HTTPClient {
    enum Response {
        case json([String: Any], statusCode: Int = 200)
        case empty(statusCode: Int)
        case failure(statusCode: Int, message: String)
    }

    var responses: [Response]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [Response] = []) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            return HTTPResponse(statusCode: 200)
        }
        let response = responses.removeFirst()
        switch response {
        case let .json(json, statusCode):
            return HTTPResponse(
                statusCode: statusCode,
                body: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            )
        case let .empty(statusCode):
            return HTTPResponse(statusCode: statusCode)
        case let .failure(statusCode, message):
            return HTTPResponse(statusCode: statusCode, body: Data(message.utf8))
        }
    }
}

fileprivate final class RecordingRunner: CommandRunning {
    struct Command: Equatable {
        var executable: String
        var arguments: [String]
    }

    var commands: [Command] = []
    var createScreenshotForSimctl: Bool
    var gitRemote: String?
    /// When true, an `xcodebuild test ... -resultBundlePath <path>` invocation
    /// fabricates an empty directory at that path so downstream code that
    /// checks for the bundle's existence behaves like it would in production.
    var fabricateXcresultBundle: Bool
    /// Stub stdout returned for any `xcresulttool get test-results summary`
    /// invocation. Tests can pre-load JSON shaped like the real tool's output.
    var xcresulttoolSummaryStdout: String?
    /// Override exit code for any `xcodebuild test` invocation. Useful for
    /// emulating build errors and test failures.
    var xcodebuildExitCode: Int32
    /// Stub stderr returned by xcodebuild when `xcodebuildExitCode != 0`.
    var xcodebuildStderr: String
    /// When true, a node invocation fabricates a dummy PNG at the last argument
    /// (the output path) so downstream fileExists checks pass.
    var createFilesForNode: Bool

    init(
        createScreenshotForSimctl: Bool = false,
        gitRemote: String? = nil,
        fabricateXcresultBundle: Bool = false,
        xcresulttoolSummaryStdout: String? = nil,
        xcodebuildExitCode: Int32 = 0,
        xcodebuildStderr: String = "",
        createFilesForNode: Bool = false
    ) {
        self.createScreenshotForSimctl = createScreenshotForSimctl
        self.gitRemote = gitRemote
        self.fabricateXcresultBundle = fabricateXcresultBundle
        self.xcresulttoolSummaryStdout = xcresulttoolSummaryStdout
        self.xcodebuildExitCode = xcodebuildExitCode
        self.xcodebuildStderr = xcodebuildStderr
        self.createFilesForNode = createFilesForNode
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        commands.append(Command(executable: executable, arguments: arguments))

        if createScreenshotForSimctl, arguments.starts(with: ["simctl", "io"]) {
            let outputPath = arguments[4]
            try Data("png".utf8).write(to: URL(fileURLWithPath: outputPath))
        }

        // node <script.js> <url> <viewportSpec> <fullPage> <waitUntil> <outputPath>
        // Detected by the first argument ending in ".js". Fabricate a dummy
        // file at the output path (last argument) so the fileExists check passes.
        if createFilesForNode, arguments.first?.hasSuffix(".js") == true,
           let outputPath = arguments.last, outputPath.hasSuffix(".png") {
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: outputURL)
        }

        if arguments == ["remote", "get-url", "origin"], let gitRemote {
            return CommandResult(exitCode: 0, stdout: gitRemote)
        }

        // xcodebuild test handling: forge a result bundle directory if asked,
        // and report the configured exit code / stderr.
        if arguments.first == "xcodebuild", arguments.dropFirst().first == "test" {
            if fabricateXcresultBundle,
               let bundleIndex = arguments.firstIndex(of: "-resultBundlePath"),
               arguments.index(after: bundleIndex) < arguments.endIndex {
                let bundlePath = arguments[arguments.index(after: bundleIndex)]
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: bundlePath),
                    withIntermediateDirectories: true
                )
            }
            return CommandResult(exitCode: xcodebuildExitCode, stderr: xcodebuildStderr)
        }

        if arguments.starts(with: ["xcresulttool", "get", "test-results", "summary"]),
           let stdout = xcresulttoolSummaryStdout {
            return CommandResult(exitCode: 0, stdout: stdout)
        }

        // `git status --porcelain`, used by `evidence accept-baseline` to
        // refuse running on a dirty tree. Default is empty (clean).
        return CommandResult(exitCode: 0)
    }
}
