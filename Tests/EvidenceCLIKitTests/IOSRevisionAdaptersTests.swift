import EvidenceCLIKit
import Foundation
import XCTest

final class IOSRevisionAdaptersTests: XCTestCase {
    func testCapturePRRunsXCTestPlanForBeforeAndAfterWithRevisionEnvironment() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-50", isDirectory: true)
        let planURL = try writePlan(in: directory, runner: .xctest, steps: [
            """
            { "name": "launch app", "kind": "launch" }
            """,
            """
            { "name": "capture home", "kind": "screenshot", "path": "home.png" }
            """
        ])
        let beforeSHA = "1010101010101010101010101010101010101010"
        let afterSHA = "2020202020202020202020202020202020202020"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ],
            createXCTestScreenshots: true
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "50",
            "--plan", planURL.path,
            "--output", output.path
        ])

        let testCommands = runner.commands.filter {
            $0.executable == "/usr/bin/xcrun" && $0.arguments.starts(with: ["xcodebuild", "test"])
        }
        XCTAssertEqual(testCommands.count, 2)
        XCTAssertEqual(testCommands[0].environment["EVIDENCE_PLAN_PATH"], planURL.path)
        XCTAssertEqual(testCommands[0].environment["EVIDENCE_OUTPUT_DIR"], output.appendingPathComponent("before", isDirectory: true).path)
        XCTAssertEqual(testCommands[0].environment["EVIDENCE_REVISION_ROLE"], "before")
        XCTAssertEqual(testCommands[1].environment["EVIDENCE_PLAN_PATH"], planURL.path)
        XCTAssertEqual(testCommands[1].environment["EVIDENCE_OUTPUT_DIR"], output.appendingPathComponent("after", isDirectory: true).path)
        XCTAssertEqual(testCommands[1].environment["EVIDENCE_REVISION_ROLE"], "after")
        XCTAssertEqual(testCommands.map(\.workingDirectory), [
            output.appendingPathComponent("worktrees/before-\(String(beforeSHA.prefix(12)))").path,
            output.appendingPathComponent("worktrees/after-\(String(afterSHA.prefix(12)))").path
        ])

        let manifest = try decodeManifest(at: output)
        let screenshotArtifacts = manifest.artifacts.filter { $0.kind == .screenshot }
        XCTAssertEqual(screenshotArtifacts.map(\.phase), [.before, .after])
        XCTAssertEqual(screenshotArtifacts.map(\.stepName), ["capture home", "capture home"])
        XCTAssertEqual(screenshotArtifacts.map(\.path), [
            output.appendingPathComponent("before/home.png").path,
            output.appendingPathComponent("after/home.png").path
        ])
        XCTAssertEqual(screenshotArtifacts.map(\.mediaType), ["image/png", "image/png"])
        XCTAssertEqual(screenshotArtifacts.map(\.fileSize), [3, 3])
        XCTAssertEqual(manifest.stepResults.filter { $0.kind == .screenshot }.map(\.stepName), [
            "capture home", "capture home"
        ])
    }

    func testXCTestPlanExecutorRecordsDeclaredVideoArtifactsForBeforeAndAfter() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-54", isDirectory: true)
        let plan = PRChangeEvidencePlan(
            repo: "ExampleOrg/ExampleApp",
            pr: 54,
            platform: .ios,
            runner: .xctest,
            ios: PRChangeEvidenceIOSSettings(
                workspace: "ios/Example.xcworkspace",
                scheme: "Example",
                bundleID: "com.example.app",
                simulatorUDID: "SIM-123",
                destination: "platform=iOS Simulator,id=SIM-123"
            ),
            steps: [
                PRChangeEvidenceStep(name: "launch app", kind: .launch),
                PRChangeEvidenceStep(name: "start flow", kind: .startVideo, path: "flow.mov"),
                PRChangeEvidenceStep(name: "capture home", kind: .screenshot, path: "home.png"),
                PRChangeEvidenceStep(name: "stop flow", kind: .stopVideo, path: "flow.mov")
            ]
        )
        let runner = IOSWorkflowRunner(
            ghJSON: "{}",
            resolvedRefs: [:],
            createXCTestScreenshots: true
        )
        let videoRecorder = FakeVideoRecorder()
        let executor = XcodeTestPlanExecutor(
            runner: runner,
            xcrunPath: "/usr/bin/xcrun",
            artifactWriter: FileArtifactWriter(),
            videoRecorder: videoRecorder,
            clock: IOSFixedEvidenceClock(date: Date(timeIntervalSince1970: 1_714_000_000))
        )

        let result = try executor.execute(EvidencePlanExecutionRequest(
            plan: plan,
            planURL: directory.appendingPathComponent(".evidence/pr-home.json"),
            outputDirectory: output,
            worktrees: [
                ComparisonWorktree(label: .before, sha: "before", path: directory.appendingPathComponent("before-worktree").path),
                ComparisonWorktree(label: .after, sha: "after", path: directory.appendingPathComponent("after-worktree").path)
            ],
            revisionBuilds: [
                revisionBuild(.before, output: output),
                revisionBuild(.after, output: output)
            ],
            ios: plan.ios!,
            launch: plan.launch
        ))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(videoRecorder.startedPaths, [
            output.appendingPathComponent("before/flow.mov").path,
            output.appendingPathComponent("after/flow.mov").path
        ])
        XCTAssertEqual(videoRecorder.stoppedPaths, videoRecorder.startedPaths)
        let videoArtifacts = result.artifacts.filter { $0.kind == .video }
        XCTAssertEqual(videoArtifacts.map(\.phase), [.before, .after])
        XCTAssertEqual(videoArtifacts.map(\.stepName), ["stop flow", "stop flow"])
        XCTAssertEqual(videoArtifacts.map(\.path), [
            output.appendingPathComponent("before/flow.mov").path,
            output.appendingPathComponent("after/flow.mov").path
        ])
        XCTAssertEqual(videoArtifacts.map(\.mediaType), ["video/quicktime", "video/quicktime"])
        XCTAssertEqual(videoArtifacts.map(\.fileSize), [3, 3])
        XCTAssertEqual(
            result.stepResults
                .filter { $0.kind == .startVideo || $0.kind == .stopVideo }
                .map(\.artifactPath),
            [
                output.appendingPathComponent("before/flow.mov").path,
                output.appendingPathComponent("before/flow.mov").path,
                output.appendingPathComponent("after/flow.mov").path,
                output.appendingPathComponent("after/flow.mov").path
            ]
        )
    }

    func testCapturePRRunsLaunchOnlySimctlFlowAndRecordsScreenshotArtifacts() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-51", isDirectory: true)
        let planURL = try writePlan(in: directory, steps: [
            """
            { "name": "launch app", "kind": "launch" }
            """,
            """
            { "name": "settle", "kind": "wait", "seconds": 0 }
            """,
            """
            { "name": "capture home", "kind": "screenshot", "path": "home.png" }
            """
        ])
        let beforeSHA = "3030303030303030303030303030303030303030"
        let afterSHA = "4040404040404040404040404040404040404040"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ],
            createSimctlScreenshots: true
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "51",
            "--plan", planURL.path,
            "--output", output.path
        ])

        let screenshotCommands = runner.commands.filter {
            $0.executable == "/usr/bin/xcrun" && $0.arguments.starts(with: ["simctl", "io", "SIM-123", "screenshot"])
        }
        XCTAssertEqual(screenshotCommands.map(\.arguments), [
            ["simctl", "io", "SIM-123", "screenshot", output.appendingPathComponent("before/home.png").path],
            ["simctl", "io", "SIM-123", "screenshot", output.appendingPathComponent("after/home.png").path]
        ])

        let manifest = try decodeManifest(at: output)
        let screenshotArtifacts = manifest.artifacts.filter { $0.kind == .screenshot }
        XCTAssertEqual(screenshotArtifacts.map(\.phase), [.before, .after])
        XCTAssertEqual(screenshotArtifacts.map(\.stepName), ["capture home", "capture home"])
        XCTAssertEqual(screenshotArtifacts.map(\.fileSize), [3, 3])
        XCTAssertEqual(screenshotArtifacts.compactMap(\.capturedAt).count, 2)
        XCTAssertEqual(manifest.stepResults.map(\.stepName), [
            "launch app", "settle", "capture home",
            "launch app", "settle", "capture home"
        ])
    }

    func testCapturePRWritesPartialManifestWhenSimctlCaptureStepFails() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-52", isDirectory: true)
        let planURL = try writePlan(in: directory, steps: [
            """
            { "name": "launch app", "kind": "launch" }
            """,
            """
            { "name": "capture home", "kind": "screenshot", "path": "home.png" }
            """
        ])
        let beforeSHA = "5050505050505050505050505050505050505050"
        let afterSHA = "6060606060606060606060606060606060606060"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ],
            createSimctlScreenshots: true,
            failingScreenshotPhase: .after
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "52",
            "--plan", planURL.path,
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("after"))
            XCTAssertTrue(message.contains("capture home"))
        }

        let manifest = try decodeManifest(at: output)
        let screenshotArtifacts = manifest.artifacts.filter { $0.kind == .screenshot }
        XCTAssertEqual(screenshotArtifacts.map(\.phase), [.before])
        XCTAssertEqual(manifest.failures.first?.stepName, "capture home")
        XCTAssertTrue(manifest.failures.first?.message.contains("after") == true)
        XCTAssertEqual(manifest.stepResults.last?.status, .failed)
        XCTAssertEqual(manifest.stepResults.last?.phase, .after)

        let report = output.appendingPathComponent("report.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.path), "capture-pr should write report.md even for partial capture failures")
        let reportMarkdown = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(reportMarkdown.contains("### Missing After Artifact"))
        XCTAssertTrue(reportMarkdown.contains("capture home"))
        XCTAssertTrue(reportMarkdown.contains("- Overall status: **failed**"))
    }

    func testSimctlPlanExecutorRecordsExplicitVideosForBeforeAndAfter() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-53", isDirectory: true)
        let plan = PRChangeEvidencePlan(
            repo: "ExampleOrg/ExampleApp",
            pr: 53,
            platform: .ios,
            runner: .simctl,
            ios: PRChangeEvidenceIOSSettings(
                scheme: "Example",
                bundleID: "com.example.app",
                simulatorUDID: "SIM-123"
            ),
            steps: [
                PRChangeEvidenceStep(name: "launch app", kind: .launch),
                PRChangeEvidenceStep(name: "start flow", kind: .startVideo, path: "flow-start.mov"),
                PRChangeEvidenceStep(name: "settle", kind: .wait, seconds: 0),
                PRChangeEvidenceStep(name: "stop flow", kind: .stopVideo, path: "flow-stop.mov")
            ]
        )
        let simulator = FakeSimulatorController()
        let videoRecorder = FakeVideoRecorder()
        let executor = SimctlPlanExecutor(
            simulator: simulator,
            videoRecorder: videoRecorder,
            artifactWriter: FileArtifactWriter(),
            clock: IOSFixedEvidenceClock(date: Date(timeIntervalSince1970: 1_714_000_000))
        )

        let result = try executor.execute(EvidencePlanExecutionRequest(
            plan: plan,
            planURL: directory.appendingPathComponent(".evidence/pr-home.json"),
            outputDirectory: output,
            worktrees: [
                ComparisonWorktree(label: .before, sha: "before", path: directory.appendingPathComponent("before-worktree").path),
                ComparisonWorktree(label: .after, sha: "after", path: directory.appendingPathComponent("after-worktree").path)
            ],
            revisionBuilds: [
                revisionBuild(.before, output: output),
                revisionBuild(.after, output: output)
            ],
            ios: plan.ios!,
            launch: plan.launch
        ))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(videoRecorder.startedPaths, [
            output.appendingPathComponent("before/flow-start.mov").path,
            output.appendingPathComponent("after/flow-start.mov").path
        ])
        XCTAssertEqual(videoRecorder.stoppedPaths, videoRecorder.startedPaths)
        let videoArtifacts = result.artifacts.filter { $0.kind == .video }
        XCTAssertEqual(videoArtifacts.map(\.phase), [.before, .after])
        XCTAssertEqual(videoArtifacts.map(\.path), videoRecorder.startedPaths)
        XCTAssertEqual(videoArtifacts.map(\.mediaType), ["video/quicktime", "video/quicktime"])
        XCTAssertEqual(videoArtifacts.map(\.fileSize), [3, 3])
        XCTAssertEqual(result.stepResults.map(\.stepName), [
            "launch app", "start flow", "settle", "stop flow",
            "launch app", "start flow", "settle", "stop flow"
        ])
    }

    func testSimctlPlanExecutorFailsWhenDeclaredWholeFlowVideoIsMissing() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-55", isDirectory: true)
        let plan = PRChangeEvidencePlan(
            repo: "ExampleOrg/ExampleApp",
            pr: 55,
            platform: .ios,
            runner: .simctl,
            ios: PRChangeEvidenceIOSSettings(
                scheme: "Example",
                bundleID: "com.example.app",
                simulatorUDID: "SIM-123"
            ),
            steps: [
                PRChangeEvidenceStep(name: "launch app", kind: .launch),
                PRChangeEvidenceStep(name: "settle", kind: .wait, seconds: 0),
                PRChangeEvidenceStep(name: "capture home", kind: .screenshot, path: "home.png")
            ],
            video: PRChangeEvidenceVideo(enabled: true, name: "home-flow")
        )
        let simulator = FakeSimulatorController()
        let videoRecorder = FakeVideoRecorder(missingOutputPhases: [.after])
        let executor = SimctlPlanExecutor(
            simulator: simulator,
            videoRecorder: videoRecorder,
            artifactWriter: FileArtifactWriter(),
            clock: IOSFixedEvidenceClock(date: Date(timeIntervalSince1970: 1_714_000_000))
        )

        let result = try executor.execute(EvidencePlanExecutionRequest(
            plan: plan,
            planURL: directory.appendingPathComponent(".evidence/pr-home.json"),
            outputDirectory: output,
            worktrees: [
                ComparisonWorktree(label: .before, sha: "before", path: directory.appendingPathComponent("before-worktree").path),
                ComparisonWorktree(label: .after, sha: "after", path: directory.appendingPathComponent("after-worktree").path)
            ],
            revisionBuilds: [
                revisionBuild(.before, output: output),
                revisionBuild(.after, output: output)
            ],
            ios: plan.ios!,
            launch: plan.launch
        ))

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.artifacts.filter { $0.kind == .video }.map(\.phase), [.before])
        XCTAssertTrue(result.failures.contains { $0.message.contains("after") && $0.message.contains("home-flow.mov") })
        XCTAssertEqual(result.stepResults.last?.phase, .after)
        XCTAssertEqual(result.stepResults.last?.status, .failed)
    }

    func testCapturePRBuildsBothRevisionsWithIsolatedDerivedDataAndManifestRecords() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-44", isDirectory: true)
        let planURL = try writePlan(in: directory)
        let beforeSHA = "1111111111111111111111111111111111111111"
        let afterSHA = "2222222222222222222222222222222222222222"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ],
            xcodebuildStdout: "Build Succeeded\n" + String(repeating: "stdout ", count: 120),
            xcodebuildStderr: String(repeating: "stderr ", count: 120)
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "44",
            "--plan", planURL.path,
            "--output", output.path
        ])

        let buildCommands = runner.commands.filter {
            $0.executable == "/usr/bin/xcrun" && $0.arguments.starts(with: ["xcodebuild", "build"])
        }
        XCTAssertEqual(buildCommands.count, 2)

        let beforeWorktree = output.appendingPathComponent("worktrees/before-\(String(beforeSHA.prefix(12)))")
        let afterWorktree = output.appendingPathComponent("worktrees/after-\(String(afterSHA.prefix(12)))")
        XCTAssertEqual(buildCommands[0].workingDirectory, beforeWorktree.path)
        XCTAssertEqual(buildCommands[1].workingDirectory, afterWorktree.path)
        XCTAssertTrue(buildCommands[0].arguments.contains(output.appendingPathComponent("derived-data/before").path))
        XCTAssertTrue(buildCommands[1].arguments.contains(output.appendingPathComponent("derived-data/after").path))
        XCTAssertTrue(buildCommands[0].arguments.contains("-workspace"))
        XCTAssertTrue(buildCommands[0].arguments.contains("ios/Example.xcworkspace"))
        XCTAssertTrue(buildCommands[0].arguments.contains("-scheme"))
        XCTAssertTrue(buildCommands[0].arguments.contains("Example"))
        XCTAssertTrue(buildCommands[0].arguments.contains("-configuration"))
        XCTAssertTrue(buildCommands[0].arguments.contains("Debug"))
        XCTAssertTrue(buildCommands[0].arguments.contains("-destination"))
        XCTAssertTrue(buildCommands[0].arguments.contains("platform=iOS Simulator,id=SIM-123"))
        XCTAssertTrue(buildCommands[0].arguments.contains("CODE_SIGNING_ALLOWED=NO"))

        let manifest = try decodeManifest(at: output)
        XCTAssertEqual(manifest.buildResult.status, .succeeded)
        XCTAssertEqual(manifest.revisionBuilds.map(\.phase), [.before, .after])
        XCTAssertEqual(manifest.revisionBuilds.map(\.exitCode), [0, 0])
        XCTAssertEqual(manifest.revisionBuilds[0].derivedDataPath, output.appendingPathComponent("derived-data/before").path)
        XCTAssertEqual(manifest.revisionBuilds[1].derivedDataPath, output.appendingPathComponent("derived-data/after").path)
        XCTAssertEqual(manifest.revisionBuilds[0].appBundlePath, output.appendingPathComponent("derived-data/before/Build/Products/Debug-iphonesimulator/Example.app").path)
        XCTAssertLessThanOrEqual(manifest.revisionBuilds[0].stdoutExcerpt.count, 2_000)
        XCTAssertLessThanOrEqual(manifest.revisionBuilds[0].stderrExcerpt.count, 2_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.revisionBuilds[0].logPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.revisionBuilds[1].logPath))
    }

    func testCapturePRInstallsAndLaunchesEachRevisionWithCleanSimulatorStateAndLaunchEnvironment() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-45", isDirectory: true)
        let planURL = try writePlan(in: directory)
        let beforeSHA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let afterSHA = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "45",
            "--plan", planURL.path,
            "--output", output.path
        ])

        let simctlCommands = runner.commands.filter {
            $0.executable == "/usr/bin/xcrun" && $0.arguments.first == "simctl"
        }
        XCTAssertTrue(simctlCommands.contains { $0.arguments == ["simctl", "boot", "SIM-123"] })
        XCTAssertTrue(simctlCommands.contains { $0.arguments == ["simctl", "bootstatus", "SIM-123", "-b"] })
        XCTAssertTrue(simctlCommands.contains { $0.arguments.starts(with: ["simctl", "ui", "SIM-123"]) })
        XCTAssertTrue(simctlCommands.contains { $0.arguments.starts(with: ["simctl", "status_bar", "SIM-123", "override"]) })

        let uninstalls = simctlCommands.filter { $0.arguments.starts(with: ["simctl", "uninstall", "SIM-123", "com.example.app"]) }
        let installs = simctlCommands.filter { $0.arguments.starts(with: ["simctl", "install", "SIM-123"]) }
        let launches = simctlCommands.filter { $0.arguments.starts(with: ["simctl", "launch", "SIM-123", "com.example.app"]) }
        XCTAssertEqual(uninstalls.count, 2)
        XCTAssertEqual(installs.count, 2)
        XCTAssertEqual(launches.count, 2)
        XCTAssertEqual(Array(launches[0].arguments.suffix(3)), ["--evidence-mode", "-UITest", "YES"])
        XCTAssertEqual(launches[0].environment["SIMCTL_CHILD_EXAMPLE_EVIDENCE_MODE"], "1")
        XCTAssertEqual(launches[1].environment["SIMCTL_CHILD_EXAMPLE_EVIDENCE_MODE"], "1")
        XCTAssertEqual(simctlCommands.last?.arguments, ["simctl", "shutdown", "SIM-123"])
    }

    func testCapturePRPreservesSimulatorStateOnlyWhenPlanOptsIn() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-46", isDirectory: true)
        let planURL = try writePlan(in: directory, preserveSimulatorState: true)
        let beforeSHA = "cccccccccccccccccccccccccccccccccccccccc"
        let afterSHA = "dddddddddddddddddddddddddddddddddddddddd"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "46",
            "--plan", planURL.path,
            "--output", output.path
        ])

        XCTAssertFalse(
            runner.commands.contains { $0.arguments.starts(with: ["simctl", "uninstall", "SIM-123", "com.example.app"]) },
            "preserve_simulator_state should skip uninstall so app container state is retained"
        )
    }

    func testCapturePRWritesFailedManifestAndNamesAfterBuildFailures() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-47", isDirectory: true)
        let planURL = try writePlan(in: directory)
        let beforeSHA = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        let afterSHA = "ffffffffffffffffffffffffffffffffffffffff"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ],
            xcodebuildStderr: "SwiftCompile failed",
            xcodebuildExitCodes: [PRChangeEvidencePhase.before: 0, PRChangeEvidencePhase.after: 65]
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "47",
            "--plan", planURL.path,
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("after build failed"), "message should name after build: \(message)")
            XCTAssertTrue(message.contains("SwiftCompile failed"), "message should include build stderr: \(message)")
        }

        let manifest = try decodeManifest(at: output)
        XCTAssertEqual(manifest.buildResult.status, .failed)
        XCTAssertEqual(manifest.revisionBuilds.map(\.phase), [.before, .after])
        XCTAssertEqual(manifest.revisionBuilds.map(\.exitCode), [0, 65])
        XCTAssertTrue(manifest.failures.contains { $0.message.contains("after build failed") })
    }

    func testCapturePRNamesSimulatorBootInstallAndLaunchFailures() throws {
        try assertSimulatorFailure(stage: IOSSimulatorFailureStage.boot, expected: "simulator boot failed")
        try assertSimulatorFailure(stage: IOSSimulatorFailureStage.install, expected: "install failed")
        try assertSimulatorFailure(stage: IOSSimulatorFailureStage.launch, expected: "launch failed")
    }

    private func assertSimulatorFailure(stage: IOSSimulatorFailureStage, expected: String) throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/\(UUID().uuidString)", isDirectory: true)
        let planURL = try writePlan(in: directory)
        let beforeSHA = "1234567890abcdef1234567890abcdef12345678"
        let afterSHA = "abcdef1234567890abcdef1234567890abcdef12"
        let runner = IOSWorkflowRunner(
            ghJSON: Self.pullRequestJSON(baseSHA: beforeSHA, headSHA: afterSHA),
            resolvedRefs: [
                "\(beforeSHA)^{commit}": beforeSHA,
                "\(afterSHA)^{commit}": afterSHA
            ],
            simulatorFailureStage: stage
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "ExampleOrg/ExampleApp",
            "--pr", "48",
            "--plan", planURL.path,
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains(expected), "message should contain \(expected): \(message)")
        }

        let manifest = try decodeManifest(at: output)
        XCTAssertEqual(manifest.buildResult.status, .succeeded)
        XCTAssertTrue(manifest.failures.contains { $0.message.contains(expected) })
    }

    private func testCLI(directory: URL, runner: IOSWorkflowRunner) -> EvidenceCLI {
        EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            currentDirectory: directory,
            toolPaths: ToolPaths(
                xcrun: "/usr/bin/xcrun",
                magick: "/bin/echo",
                ffmpeg: "/bin/echo",
                git: "/usr/bin/git",
                node: "/bin/echo",
                gh: "/usr/bin/gh"
            ),
            clock: IOSFixedEvidenceClock(date: Date(timeIntervalSince1970: 1_714_000_000))
        )
    }

    private func writePlan(
        in directory: URL,
        runner: RunnerCapability = .simctl,
        preserveSimulatorState: Bool = false,
        steps: [String] = [
            """
            { "name": "launch", "kind": "launch" }
            """,
            """
            { "name": "settle", "kind": "wait", "seconds": 0 }
            """
        ]
    ) throws -> URL {
        let planDirectory = directory.appendingPathComponent(".evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: planDirectory, withIntermediateDirectories: true)
        let url = planDirectory.appendingPathComponent("pr-home.json")
        let renderedSteps = steps.joined(separator: ",\n")
        let json = """
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 44,
          "platform": "ios",
          "runner": "\(runner.rawValue)",
          "ios": {
            "workspace": "ios/Example.xcworkspace",
            "scheme": "Example",
            "bundle_id": "com.example.app",
            "simulator_udid": "SIM-123",
            "destination": "platform=iOS Simulator,id=SIM-123",
            "configuration": "Debug",
            "extra_xcodebuild_arguments": ["CODE_SIGNING_ALLOWED=NO"],
            "preserve_simulator_state": \(preserveSimulatorState ? "true" : "false")
          },
          "launch": {
            "arguments": ["--evidence-mode", "-UITest", "YES"],
            "environment": {
              "EXAMPLE_EVIDENCE_MODE": "1"
            }
          },
          "steps": [
            \(renderedSteps)
          ]
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func decodeManifest(at output: URL) throws -> PRChangeEvidenceManifest {
        try JSONDecoder().decode(
            PRChangeEvidenceManifest.self,
            from: Data(contentsOf: output.appendingPathComponent("manifest.json"))
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func revisionBuild(_ phase: PRChangeEvidencePhase, output: URL) -> RevisionBuildResult {
        RevisionBuildResult(
            phase: phase,
            command: ["/usr/bin/xcrun", "xcodebuild", "build"],
            exitCode: 0,
            durationSeconds: 1,
            stdoutExcerpt: "",
            stderrExcerpt: "",
            appBundlePath: output.appendingPathComponent("apps/\(phase.rawValue)/Example.app").path,
            derivedDataPath: output.appendingPathComponent("derived-data/\(phase.rawValue)").path,
            logPath: output.appendingPathComponent("logs/build-\(phase.rawValue).log").path
        )
    }

    private static func pullRequestJSON(baseSHA: String, headSHA: String) -> String {
        """
        {
          "url": "https://github.com/ExampleOrg/ExampleApp/pull/44",
          "title": "Resolve visual evidence",
          "state": "OPEN",
          "baseRefName": "main",
          "headRefName": "feature/evidence",
          "baseRefOid": "\(baseSHA)",
          "headRefOid": "\(headSHA)",
          "mergeCommit": null
        }
        """
    }
}

private final class IOSWorkflowRunner: CommandRunning {
    struct Command: Equatable {
        var executable: String
        var arguments: [String]
        var workingDirectory: String?
        var environment: [String: String]
    }

    private let ghJSON: String
    private let resolvedRefs: [String: String]
    private let xcodebuildStdout: String
    private let xcodebuildStderr: String
    private let xcodebuildExitCodes: [PRChangeEvidencePhase: Int32]
    private let simulatorFailureStage: IOSSimulatorFailureStage?
    private let createXCTestScreenshots: Bool
    private let createSimctlScreenshots: Bool
    private let failingScreenshotPhase: PRChangeEvidencePhase?
    private(set) var commands: [Command] = []

    init(
        ghJSON: String,
        resolvedRefs: [String: String],
        xcodebuildStdout: String = "Build Succeeded",
        xcodebuildStderr: String = "",
        xcodebuildExitCodes: [PRChangeEvidencePhase: Int32] = [:],
        simulatorFailureStage: IOSSimulatorFailureStage? = nil,
        createXCTestScreenshots: Bool = false,
        createSimctlScreenshots: Bool = false,
        failingScreenshotPhase: PRChangeEvidencePhase? = nil
    ) {
        self.ghJSON = ghJSON
        self.resolvedRefs = resolvedRefs
        self.xcodebuildStdout = xcodebuildStdout
        self.xcodebuildStderr = xcodebuildStderr
        self.xcodebuildExitCodes = xcodebuildExitCodes
        self.simulatorFailureStage = simulatorFailureStage
        self.createXCTestScreenshots = createXCTestScreenshots
        self.createSimctlScreenshots = createSimctlScreenshots
        self.failingScreenshotPhase = failingScreenshotPhase
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        try run(executable, arguments, workingDirectory: nil, environment: [:])
    }

    func run(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]
    ) throws -> CommandResult {
        commands.append(Command(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory?.path,
            environment: environment
        ))

        if executable == "/usr/bin/gh" {
            return CommandResult(exitCode: 0, stdout: ghJSON)
        }

        if executable == "/usr/bin/git" {
            return try git(arguments)
        }

        if executable == "/usr/bin/xcrun", arguments.starts(with: ["xcodebuild", "build"]) {
            return try xcodebuild(arguments)
        }

        if executable == "/usr/bin/xcrun", arguments.starts(with: ["xcodebuild", "test"]) {
            return try xcodebuildTest(arguments, environment: environment)
        }

        if executable == "/usr/bin/xcrun", arguments.first == "simctl" {
            return simctl(arguments)
        }

        return CommandResult(exitCode: 0)
    }

    private func git(_ arguments: [String]) throws -> CommandResult {
        guard let command = gitCommand(arguments) else {
            return CommandResult(exitCode: 0)
        }
        if command.starts(with: ["fetch"]) {
            return CommandResult(exitCode: 0)
        }
        if command.starts(with: ["rev-parse", "--verify"]), command.count == 3 {
            if let resolved = resolvedRefs[command[2]] {
                return CommandResult(exitCode: 0, stdout: "\(resolved)\n")
            }
            return CommandResult(exitCode: 1, stderr: "fatal: needed a single revision")
        }
        if command.starts(with: ["worktree", "add"]) {
            let path = command[3]
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
            return CommandResult(exitCode: 0)
        }
        if command.starts(with: ["status", "--porcelain"]) {
            return CommandResult(exitCode: 0)
        }
        return CommandResult(exitCode: 0)
    }

    private func xcodebuild(_ arguments: [String]) throws -> CommandResult {
        guard let derivedDataPath = value(after: "-derivedDataPath", in: arguments) else {
            return CommandResult(exitCode: 65, stderr: "missing derived data")
        }
        let phase: PRChangeEvidencePhase = derivedDataPath.hasSuffix("/after") ? .after : .before
        let product = URL(fileURLWithPath: derivedDataPath)
            .appendingPathComponent("Build/Products/Debug-iphonesimulator/Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        return CommandResult(
            exitCode: xcodebuildExitCodes[phase] ?? 0,
            stdout: xcodebuildStdout,
            stderr: xcodebuildStderr
        )
    }

    private func xcodebuildTest(
        _ arguments: [String],
        environment: [String: String]
    ) throws -> CommandResult {
        if createXCTestScreenshots,
           let output = environment["EVIDENCE_OUTPUT_DIR"] {
            let screenshot = URL(fileURLWithPath: output, isDirectory: true)
                .appendingPathComponent("home.png")
            try FileManager.default.createDirectory(at: screenshot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: screenshot)
        }
        return CommandResult(exitCode: 0, stdout: "Test Succeeded")
    }

    private func simctl(_ arguments: [String]) -> CommandResult {
        if simulatorFailureStage == .boot, arguments.starts(with: ["simctl", "boot"]) {
            return CommandResult(exitCode: 1, stderr: "boot denied")
        }
        if simulatorFailureStage == .install, arguments.starts(with: ["simctl", "install"]) {
            return CommandResult(exitCode: 1, stderr: "install denied")
        }
        if simulatorFailureStage == .launch, arguments.starts(with: ["simctl", "launch"]) {
            return CommandResult(exitCode: 1, stderr: "launch denied")
        }
        if arguments.starts(with: ["simctl", "io", "SIM-123", "screenshot"]) {
            guard let outputPath = arguments.last else {
                return CommandResult(exitCode: 1, stderr: "missing screenshot path")
            }
            if failingScreenshotPhase == phase(forArtifactPath: outputPath) {
                return CommandResult(exitCode: 1, stderr: "screenshot denied")
            }
            if createSimctlScreenshots {
                let outputURL = URL(fileURLWithPath: outputPath)
                try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data("png".utf8).write(to: outputURL)
            }
        }
        return CommandResult(exitCode: 0)
    }

    private func phase(forArtifactPath path: String) -> PRChangeEvidencePhase? {
        if path.contains("/before/") {
            return .before
        }
        if path.contains("/after/") {
            return .after
        }
        return nil
    }

    private func gitCommand(_ arguments: [String]) -> [String]? {
        guard arguments.count >= 3, arguments[0] == "-C" else {
            return nil
        }
        return Array(arguments.dropFirst(2))
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }
}

private enum IOSSimulatorFailureStage {
    case boot
    case install
    case launch
}

private struct IOSFixedEvidenceClock: EvidenceClock {
    var date: Date

    func now() -> Date {
        date
    }
}

private final class FakeSimulatorController: SimulatorControlling {
    func resolve(_ ios: PRChangeEvidenceIOSSettings) throws -> SimulatorSelection {
        SimulatorSelection(name: ios.simulator, udid: ios.simulatorUDID ?? "SIM-123")
    }

    func boot(_ selection: SimulatorSelection) throws {}

    func installAndLaunch(
        phase: PRChangeEvidencePhase,
        appBundle: AppBundleLocation,
        context: SimulatorRunContext
    ) throws {}

    func screenshot(_ selection: SimulatorSelection, outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: outputURL)
    }

    func openURL(_ url: String, selection: SimulatorSelection) throws {}

    func terminate(bundleID: String, selection: SimulatorSelection) throws {}

    func shutdown(_ selection: SimulatorSelection) throws {}
}

private final class FakeVideoRecorder: VideoRecording {
    private(set) var startedPaths: [String] = []
    private(set) var stoppedPaths: [String] = []
    var missingOutputPhases: Set<PRChangeEvidencePhase>

    init(missingOutputPhases: Set<PRChangeEvidencePhase> = []) {
        self.missingOutputPhases = missingOutputPhases
    }

    func start(udid: String, outputURL: URL) throws -> VideoRecordingSession {
        startedPaths.append(outputURL.path)
        return VideoRecordingSession(udid: udid, outputPath: outputURL.path)
    }

    func stop(_ session: VideoRecordingSession) throws {
        stoppedPaths.append(session.outputPath)
        if missingOutputPhases.contains(phase(forArtifactPath: session.outputPath)) {
            return
        }
        let url = URL(fileURLWithPath: session.outputPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mov".utf8).write(to: url)
    }

    private func phase(forArtifactPath path: String) -> PRChangeEvidencePhase {
        path.contains("/after/") ? .after : .before
    }
}
