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
        screenshot_targets = ["6.9", "5.5", "ipad-13"]
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
        XCTAssertEqual(config.screenshotTargets.map(\.name), ["6.9", "5.5", "ipad-13"])
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

    // MARK: - visual regression mode

    func testDiffConfigParsesIgnoreRegionsAndDefaults() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        diff_threshold = 0.005
        diff_ignore_regions = ["0,0,300x60", "0,2700,1290x96"]
        diff_baseline_dir = "docs/baselines"
        diff_accept_allow_dirty = true
        diff_fuzz_percent = 5
        """)

        let config = try EvidenceConfig.parse(document)
        XCTAssertEqual(config.diff.threshold, 0.005)
        XCTAssertEqual(config.diff.baselineDirectory, "docs/baselines")
        XCTAssertTrue(config.diff.acceptAllowDirty)
        XCTAssertEqual(config.diff.fuzzPercent, 5)
        XCTAssertEqual(config.diff.ignoreRegions, [
            DiffRegion(x: 0, y: 0, width: 300, height: 60),
            DiffRegion(x: 0, y: 2700, width: 1290, height: 96)
        ])
    }

    func testDiffConfigRejectsMalformedIgnoreRegion() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        diff_ignore_regions = ["0,0,not-a-rect"]
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'diff_ignore_regions': '0,0,not-a-rect' is not in 'X,Y,WxH' form (e.g. '0,0,200x100').")
            )
        }
    }

    func testDiffReportsMatchWhenAllScenesUnderThreshold() throws {
        let directory = try diffProject(threshold: 0.01)
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "iPhone 16/home.png")
        try writeBaselineImage(in: directory, baselineDir: "docs/baselines", scene: "iPhone 16/home.png")

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        runner.magickCompareStubs["home.png"] = (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) })

        let exitCode = cli.run(["diff"])

        XCTAssertEqual(exitCode, 0)
        let reportData = try Data(contentsOf: directory.appendingPathComponent("docs/build-evidence/diff/diff-report.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: reportData) as? [String: Any])
        XCTAssertEqual(json["threshold"] as? Double, 0.01)
        let scenes = try XCTUnwrap(json["scenes"] as? [[String: Any]])
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes.first?["status"] as? String, "match")
        XCTAssertTrue(output.joined(separator: "\n").contains("All 1 scene(s) match"))
    }

    func testDiffReturnsExitCodeOneWhenSceneExceedsThreshold() throws {
        let directory = try diffProject(threshold: 0.001)
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "home.png")
        try writeBaselineImage(in: directory, baselineDir: "docs/baselines", scene: "home.png")

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        // 5000 / 1_000_000 = 0.5% — well above the 0.1% threshold.
        runner.magickCompareStubs["home.png"] = (exitCode: 1, differingPixels: 5_000, totalPixels: 1_000_000)
        var stderr: [String] = []
        let cli = EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            stderr: { stderr.append($0) },
            currentDirectory: directory,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo")
        )

        let exitCode = cli.run(["diff"])

        XCTAssertEqual(exitCode, 1, "regression should produce exit code 1")
        XCTAssertTrue(stderr.joined().contains("exceeded threshold"))
    }

    func testDiffReturnsExitCodeTwoWhenBaselineMissing() throws {
        let directory = try diffProject(threshold: 0.01)
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "iPhone 16/onboarding.png")
        // Note: no baseline file written.

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        var stderr: [String] = []
        let cli = EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            stderr: { stderr.append($0) },
            currentDirectory: directory,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo")
        )

        let exitCode = cli.run(["diff"])

        XCTAssertEqual(exitCode, 2, "missing baseline should produce exit code 2")
        XCTAssertTrue(stderr.joined().contains("missing baseline"))
        // The diff command never ran for missing baselines — we should NOT
        // see a `compare` invocation.
        XCTAssertFalse(runner.commands.contains { $0.arguments.first == "compare" })
    }

    func testDiffMasksIgnoreRegionsBeforeCompare() throws {
        let directory = try diffProject(
            threshold: 0.01,
            extraLines: ["diff_ignore_regions = [\"0,0,300x60\"]"]
        )
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "home.png")
        try writeBaselineImage(in: directory, baselineDir: "docs/baselines", scene: "home.png")

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        runner.fabricateMagickMaskOutput = true
        runner.magickCompareStubs["home.png"] = (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)
        let cli = testCLI(directory: directory, runner: runner)

        let exitCode = cli.run(["diff"])

        XCTAssertEqual(exitCode, 0)
        // Two mask calls (baseline + actual) should precede the compare.
        let maskCalls = runner.commands.filter { $0.arguments.contains("-fill") && $0.arguments.contains("-draw") }
        XCTAssertEqual(maskCalls.count, 2, "expected one mask call per side, got \(maskCalls.count)")
        let drawArguments = maskCalls.flatMap { command -> [String] in
            command.arguments.enumerated().compactMap { offset, arg in
                arg == "-draw" ? command.arguments[offset + 1] : nil
            }
        }
        XCTAssertTrue(drawArguments.allSatisfy { $0 == "rectangle 0,0 300,60" }, "unexpected mask rectangles: \(drawArguments)")

        // The compare call should reference the masked variants, not the raw
        // baseline/actual files — that's the whole point.
        let compareCall = try XCTUnwrap(runner.commands.first { $0.arguments.first == "compare" })
        XCTAssertTrue(compareCall.arguments.contains { $0.hasSuffix(".baseline.masked.png") })
        XCTAssertTrue(compareCall.arguments.contains { $0.hasSuffix(".actual.masked.png") })
    }

    func testDiffReportsPerDeviceBaselinesIndependently() throws {
        let directory = try diffProject(threshold: 0.01)
        // Two scenes per device, both devices share the same scene names.
        for device in ["iPhone 16", "iPad Pro 13"] {
            for scene in ["home.png", "settings.png"] {
                try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "\(device)/\(scene)")
                try writeBaselineImage(in: directory, baselineDir: "docs/baselines", scene: "\(device)/\(scene)")
            }
        }

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        // Only iPad/settings regresses; everything else matches.
        runner.magickCompareStubs["home.png"] = (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)
        // settings.png has no per-baseline path discrimination in the stub
        // map, so we'd flag both. Override iPhone settings to match.
        runner.magickCompareStubs["settings.png"] = (exitCode: 1, differingPixels: 50_000, totalPixels: 1_000_000)
        let cli = testCLI(directory: directory, runner: runner)

        let exitCode = cli.run(["diff"])

        // Exit 1 because at least one regression exists.
        XCTAssertEqual(exitCode, 1)
        let reportData = try Data(contentsOf: directory.appendingPathComponent("docs/build-evidence/diff/diff-report.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: reportData) as? [String: Any])
        let scenes = try XCTUnwrap(json["scenes"] as? [[String: Any]])
        XCTAssertEqual(scenes.count, 4, "expected 4 scenes (2 devices x 2 scenes), got \(scenes.count)")
        // Compare calls were issued per device — verify with the recorded
        // baseline argument.
        let compareCalls = runner.commands.filter { $0.arguments.first == "compare" }
        XCTAssertEqual(compareCalls.count, 4)
        let baselineDevices = Set(compareCalls.compactMap { call -> String? in
            // Layout ends with [..., baseline, actual, output]. Pull the
            // device folder name from the baseline path.
            guard let baseline = call.arguments.dropLast(2).last else { return nil }
            let url = URL(fileURLWithPath: String(baseline))
            return url.deletingLastPathComponent().lastPathComponent
        })
        XCTAssertEqual(baselineDevices, ["iPhone 16", "iPad Pro 13"])
    }

    func testDiffWritesPRMarkdownToFileWhenRequested() throws {
        let directory = try diffProject(threshold: 0.01, rawBaseURL: "https://raw.githubusercontent.com/example/app/main")
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "home.png")
        try writeBaselineImage(in: directory, baselineDir: "docs/baselines", scene: "home.png")

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        runner.magickCompareStubs["home.png"] = (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)
        let cli = testCLI(directory: directory, runner: runner)

        let exitCode = cli.run(["diff", "--markdown", "docs/build-evidence/diff.md"])

        XCTAssertEqual(exitCode, 0)
        let markdown = try String(contentsOf: directory.appendingPathComponent("docs/build-evidence/diff.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("Visual regression report"))
        XCTAssertTrue(markdown.contains("| `home` |"))
    }

    func testAcceptBaselineRefusesDirtyTreeUnlessForced() throws {
        let directory = try diffProject(threshold: 0.01)
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "home.png")

        let runner = RecordingRunner()
        runner.gitStatusStdout = " M Sources/EvidenceCLIKit/EvidenceCLI.swift\n"
        var stderr: [String] = []
        let cli = EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            stderr: { stderr.append($0) },
            currentDirectory: directory,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo")
        )

        let dirtyExit = cli.run(["accept-baseline"])
        XCTAssertEqual(dirtyExit, 1)
        XCTAssertTrue(stderr.joined().contains("Refusing to accept baseline"))

        // No baseline was written.
        let baseline = directory.appendingPathComponent("docs/baselines/home.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseline.path))

        // --force overrides the check.
        let forcedExit = cli.run(["accept-baseline", "--force"])
        XCTAssertEqual(forcedExit, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseline.path))
    }

    func testDiffSecondRunIgnoresPriorDiffOutputs() throws {
        let directory = try diffProject(threshold: 0.01)
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "home.png")
        try writeBaselineImage(in: directory, baselineDir: "docs/baselines", scene: "home.png")

        let runner = RecordingRunner()
        runner.fabricateMagickCompareOutput = true
        runner.magickCompareStubs["home.png"] = (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)
        let cli = testCLI(directory: directory, runner: runner)

        // First run leaves `docs/build-evidence/diff/home.png` on disk via
        // the runner's fabricator — exactly what production would do.
        XCTAssertEqual(cli.run(["diff"]), 0)
        let diffPath = directory.appendingPathComponent("docs/build-evidence/diff/home.png").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: diffPath))

        // Second run must NOT pick up the diff output as a new scene to
        // compare against `<baseline>/diff/home.png` (which doesn't exist).
        let secondRunner = RecordingRunner()
        secondRunner.fabricateMagickCompareOutput = true
        secondRunner.magickCompareStubs["home.png"] = (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)
        let cli2 = testCLI(directory: directory, runner: secondRunner)
        XCTAssertEqual(cli2.run(["diff"]), 0)
        // Only one compare call (home.png) — not two.
        let compareCalls = secondRunner.commands.filter { $0.arguments.first == "compare" }
        XCTAssertEqual(compareCalls.count, 1, "second run should not diff prior diff outputs")
    }

    func testAcceptBaselineCopiesPNGsAndSkipsDiffOutputs() throws {
        let directory = try diffProject(threshold: 0.01)
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "iPhone 16/home.png")
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "iPhone 16/settings.png")
        // Simulate a previous run leaving diff outputs in place — these must
        // NOT be copied into the baseline tree.
        try writeRunImage(in: directory, evidenceDir: "docs/build-evidence", scene: "diff/iPhone 16/home.png")

        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        let exitCode = cli.run(["accept-baseline"])

        XCTAssertEqual(exitCode, 0)
        let homePath = directory.appendingPathComponent("docs/baselines/iPhone 16/home.png").path
        let settingsPath = directory.appendingPathComponent("docs/baselines/iPhone 16/settings.png").path
        let strayDiffPath = directory.appendingPathComponent("docs/baselines/diff/iPhone 16/home.png").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: homePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayDiffPath), "diff/ outputs must not flow into the baseline tree")
    }

    // MARK: helpers

    private func diffProject(
        threshold: Double,
        rawBaseURL: String? = nil,
        extraLines: [String] = []
    ) throws -> URL {
        var lines = ["diff_threshold = \(threshold)"]
        lines.append(contentsOf: extraLines)
        return try configuredProject(rawBaseURL: rawBaseURL, extraLines: lines)
    }

    private func writeRunImage(in directory: URL, evidenceDir: String, scene: String) throws {
        let url = directory.appendingPathComponent(evidenceDir).appendingPathComponent(scene)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: url)
    }

    private func writeBaselineImage(in directory: URL, baselineDir: String, scene: String) throws {
        let url = directory.appendingPathComponent(baselineDir).appendingPathComponent(scene)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: url)
    }

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

    private func testCLI(
        directory: URL,
        runner: RecordingRunner,
        stdout: @escaping (String) -> Void = { _ in },
        cacheDirectory: URL? = nil,
        httpClient: HTTPClient = MockHTTPClient()
    ) -> EvidenceCLI {
        EvidenceCLI(
            runner: runner,
            stdout: stdout,
            currentDirectory: directory,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo"),
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
    /// Per-baseline-path stub for `magick compare -metric AE`. The key is the
    /// last component of the *baseline* image path (the second-to-last
    /// argument before `output`). The value is `(exitCode, differingPixels)`.
    /// Default behavior (no stub for a path) is "exit 0, 0 differing pixels"
    /// so a baseline-by-baseline test only has to declare the regressions.
    var magickCompareStubs: [String: (exitCode: Int32, differingPixels: Int, totalPixels: Int)] = [:]
    /// Stdout returned by `git status --porcelain`. Empty by default (clean
    /// tree), so `evidence accept-baseline` succeeds without configuration.
    var gitStatusStdout: String = ""
    /// Whether the runner should physically copy/write into the path passed
    /// as the third positional argument to `magick compare`. The CLI checks
    /// for the diff PNG's existence before emitting the markdown URL, so
    /// tests that exercise the full path need a real file on disk.
    var fabricateMagickCompareOutput: Bool = false
    /// Whether the masking step (`magick <src> -fill black -draw ...`) should
    /// produce its destination file on disk. Mirrors the production tool's
    /// behaviour; only relevant for ignore-region tests.
    var fabricateMagickMaskOutput: Bool = false

    init(
        createScreenshotForSimctl: Bool = false,
        gitRemote: String? = nil,
        fabricateXcresultBundle: Bool = false,
        xcresulttoolSummaryStdout: String? = nil,
        xcodebuildExitCode: Int32 = 0,
        xcodebuildStderr: String = ""
    ) {
        self.createScreenshotForSimctl = createScreenshotForSimctl
        self.gitRemote = gitRemote
        self.fabricateXcresultBundle = fabricateXcresultBundle
        self.xcresulttoolSummaryStdout = xcresulttoolSummaryStdout
        self.xcodebuildExitCode = xcodebuildExitCode
        self.xcodebuildStderr = xcodebuildStderr
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        commands.append(Command(executable: executable, arguments: arguments))

        if createScreenshotForSimctl, arguments.starts(with: ["simctl", "io"]) {
            let outputPath = arguments[4]
            try Data("png".utf8).write(to: URL(fileURLWithPath: outputPath))
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
        if arguments == ["status", "--porcelain"] {
            return CommandResult(exitCode: 0, stdout: gitStatusStdout)
        }

        // `magick compare -metric AE [-fuzz N%] <baseline> <actual> <output>`.
        // Stub by baseline filename so a test can express "home.png is a
        // regression with 4200 differing pixels" without touching disk.
        if arguments.first == "compare", arguments.count >= 3, arguments.last != nil {
            // Layout: ["compare", "-metric", "AE", (optional "-fuzz", "N%"),
            //          <baseline>, <actual>, <output>].
            let baseline = arguments[arguments.count - 3]
            let output = arguments[arguments.count - 1]
            let key = (baseline as NSString).lastPathComponent
            // Strip masked-suffix variant so an ignore-region run still
            // matches the same stub key as the underlying baseline.
            let normalizedKey = key
                .replacingOccurrences(of: ".baseline.masked.png", with: ".png")
            let stub = magickCompareStubs[normalizedKey]
                ?? magickCompareStubs[key]
                ?? (exitCode: 0, differingPixels: 0, totalPixels: 1_000_000)

            if fabricateMagickCompareOutput {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: output).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("png".utf8).write(to: URL(fileURLWithPath: output))
            }

            // ImageMagick prints the AE count to stderr; we also embed a
            // `total=N` token for the parser path that wants a denominator.
            let combined = "\(stub.differingPixels) total=\(stub.totalPixels)"
            return CommandResult(
                exitCode: stub.exitCode,
                stdout: "",
                stderr: combined
            )
        }

        // `magick <src> -fill black -draw "rectangle ..." <dst>` for ignore
        // regions. Optionally fabricate the destination so downstream
        // `compare` calls find a real file.
        if arguments.count >= 4, arguments.contains("-fill"), arguments.contains("-draw"),
           let dst = arguments.last {
            if fabricateMagickMaskOutput {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: dst).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("png".utf8).write(to: URL(fileURLWithPath: dst))
            }
            return CommandResult(exitCode: 0)
        }

        return CommandResult(exitCode: 0)
    }
}
