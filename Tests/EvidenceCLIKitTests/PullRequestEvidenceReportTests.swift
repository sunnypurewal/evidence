import EvidenceCLIKit
import Foundation
import XCTest

final class PullRequestEvidenceReportTests: XCTestCase {
    func testRendererWritesSuccessfulMarkdownAndComparisonImageRequest() throws {
        let output = try outputDirectory()
        try writeFixtureArtifacts(in: output)
        let renderer = RecordingComparisonImageRenderer()
        let reporter = RenderPullRequestEvidenceReport(
            comparisonRenderer: renderer,
            fileManager: .default
        )

        let report = try reporter.writeReport(
            manifest: successfulManifest(output: output),
            plan: comparisonPlan(),
            outputDirectory: output
        )

        let reportURL = output.appendingPathComponent("report.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(report.markdown, try String(contentsOf: reportURL, encoding: .utf8))
        XCTAssertTrue(report.markdown.contains("# PR Change Evidence Report"))
        XCTAssertTrue(report.markdown.contains("- Repository: `ExampleOrg/ExampleApp`"))
        XCTAssertTrue(report.markdown.contains("- Pull request: [#77 Render evidence](https://github.com/ExampleOrg/ExampleApp/pull/77)"))
        XCTAssertTrue(report.markdown.contains("- Before SHA: `1111111111111111111111111111111111111111`"))
        XCTAssertTrue(report.markdown.contains("- After SHA: `2222222222222222222222222222222222222222`"))
        XCTAssertTrue(report.markdown.contains("- Runner mode: `simctl`"))
        XCTAssertTrue(report.markdown.contains("- Simulator: `iPhone 17 Pro` (`SIM-123`)"))
        XCTAssertTrue(report.markdown.contains("- Command: `evidence capture-pr --repo ExampleOrg/ExampleApp --pr 77`"))
        XCTAssertTrue(report.markdown.contains("- Started: `2026-05-18T00:00:00Z`"))
        XCTAssertTrue(report.markdown.contains("- Completed: `2026-05-18T00:02:00Z`"))
        XCTAssertTrue(report.markdown.contains("- Overall status: **succeeded**"))

        XCTAssertTrue(report.markdown.contains("## Visual Comparisons"))
        XCTAssertTrue(report.markdown.contains("![Home screen comparison](comparisons/home-screen.png)"))
        XCTAssertTrue(report.markdown.contains("Artifacts: before `before/home.png`, after `after/home.png`"))
        XCTAssertTrue(report.markdown.contains("Before video: [before/flow.mov](before/flow.mov)"))
        XCTAssertTrue(report.markdown.contains("After video: [after/flow.mov](after/flow.mov)"))

        let request = try XCTUnwrap(renderer.requests.first)
        XCTAssertEqual(request.sceneName, "Home screen")
        XCTAssertEqual(request.beforeURL.path, output.appendingPathComponent("before/home.png").path)
        XCTAssertEqual(request.afterURL.path, output.appendingPathComponent("after/home.png").path)
        XCTAssertEqual(request.outputURL.path, output.appendingPathComponent("comparisons/home-screen.png").path)
        XCTAssertEqual(request.beforeLabel, "Home screen - Before 1111111")
        XCTAssertEqual(request.afterLabel, "Home screen - After 2222222")
    }

    func testRendererFallsBackToRawLinksWhenComparisonRenderingIsSkipped() throws {
        let output = try outputDirectory()
        try writeFixtureArtifacts(in: output)
        let reporter = RenderPullRequestEvidenceReport(
            comparisonRenderer: SkippingComparisonImageRenderer(reason: "ImageMagick is not available"),
            fileManager: .default
        )

        let report = try reporter.writeReport(
            manifest: successfulManifest(output: output),
            plan: comparisonPlan(),
            outputDirectory: output
        )

        XCTAssertTrue(report.markdown.contains("Contact-sheet rendering skipped: ImageMagick is not available"))
        XCTAssertTrue(report.markdown.contains("![Home screen before](before/home.png)"))
        XCTAssertTrue(report.markdown.contains("![Home screen after](after/home.png)"))
    }

    func testRendererNamesMissingAfterArtifact() throws {
        let output = try outputDirectory()
        try FileManager.default.createDirectory(
            at: output.appendingPathComponent("before", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("png".utf8).write(to: output.appendingPathComponent("before/home.png"))
        var manifest = successfulManifest(output: output)
        manifest.artifacts = manifest.artifacts.filter { artifact in
            artifact.kind != .screenshot || artifact.phase == .before
        }
        manifest.stepResults = [
            CaptureStepResult(
                phase: .before,
                stepName: "Home screen",
                kind: .screenshot,
                status: .succeeded,
                artifactPath: output.appendingPathComponent("before/home.png").path,
                startedAt: "2026-05-18T00:00:10Z",
                completedAt: "2026-05-18T00:00:11Z"
            ),
            CaptureStepResult(
                phase: .after,
                stepName: "Home screen",
                kind: .screenshot,
                status: .failed,
                message: "screenshot denied",
                startedAt: "2026-05-18T00:00:20Z",
                completedAt: "2026-05-18T00:00:21Z"
            )
        ]
        manifest.failures = [
            PRChangeEvidenceFailureSummary(stepName: "Home screen", message: "after capture failed", artifactPath: output.appendingPathComponent("after/home.png").path)
        ]

        let report = try RenderPullRequestEvidenceReport(
            comparisonRenderer: RecordingComparisonImageRenderer(),
            fileManager: .default
        ).writeReport(manifest: manifest, plan: comparisonPlan(), outputDirectory: output)

        XCTAssertTrue(report.markdown.contains("### Missing After Artifact"))
        XCTAssertTrue(report.markdown.contains("Home screen"))
        XCTAssertTrue(report.markdown.contains("expected `after/home.png`"))
        XCTAssertTrue(report.markdown.contains("- Overall status: **failed**"))
    }

    func testRendererNamesMissingWholeFlowVideoWhenPlanVideoIsEnabled() throws {
        let output = try outputDirectory()
        var manifest = successfulManifest(output: output)
        manifest.artifacts = manifest.artifacts.filter { artifact in
            artifact.kind != .video || artifact.phase == .before
        }

        var plan = comparisonPlan()
        plan.video = PRChangeEvidenceVideo(enabled: true, name: "home-flow")
        plan.steps = [
            PRChangeEvidenceStep(name: "Launch app", kind: .launch),
            PRChangeEvidenceStep(name: "Home screen", kind: .screenshot, path: "home.png")
        ]

        let report = try RenderPullRequestEvidenceReport(
            comparisonRenderer: RecordingComparisonImageRenderer(),
            fileManager: .default
        ).writeReport(manifest: manifest, plan: plan, outputDirectory: output)

        XCTAssertTrue(report.markdown.contains("### Missing After Artifact"))
        XCTAssertTrue(report.markdown.contains("home-flow: expected `after/home-flow.mov`"))
        XCTAssertTrue(report.markdown.contains("- Overall status: **partial**"))
    }

    func testRendererNamesBuildFailureAndReportOnlyPartialOutputWithoutRawLogs() throws {
        let output = try outputDirectory()
        var manifest = successfulManifest(output: output)
        manifest.buildResult = PRChangeEvidenceBuildResult(
            status: .failed,
            logPath: output.appendingPathComponent("logs").path,
            durationSeconds: 14
        )
        manifest.revisionBuilds = [
            RevisionBuildResult(
                phase: .after,
                command: ["/usr/bin/xcrun", "xcodebuild", "build"],
                exitCode: 65,
                durationSeconds: 14,
                stdoutExcerpt: "Build started",
                stderrExcerpt: "SwiftCompile failed with a very noisy compiler log",
                appBundlePath: output.appendingPathComponent("DerivedData/Example.app").path,
                derivedDataPath: output.appendingPathComponent("DerivedData").path,
                logPath: output.appendingPathComponent("logs/build-after.log").path
            )
        ]
        manifest.artifacts = [
            CapturedArtifact(kind: .manifest, path: output.appendingPathComponent("manifest.json").path),
            CapturedArtifact(kind: .log, phase: .after, path: output.appendingPathComponent("logs/build-after.log").path, stepName: "after build")
        ]
        manifest.stepResults = []
        manifest.failures = [
            PRChangeEvidenceFailureSummary(message: "after build failed with exit code 65. SwiftCompile failed", artifactPath: output.appendingPathComponent("logs/build-after.log").path)
        ]

        let report = try RenderPullRequestEvidenceReport(
            comparisonRenderer: RecordingComparisonImageRenderer(),
            fileManager: .default
        ).writeReport(manifest: manifest, plan: comparisonPlan(), outputDirectory: output)

        XCTAssertTrue(report.markdown.contains("### Build Failure"))
        XCTAssertTrue(report.markdown.contains("after build failed with exit code 65"))
        XCTAssertTrue(report.markdown.contains("[logs/build-after.log](logs/build-after.log)"))
        XCTAssertTrue(report.markdown.contains("### Report-Only Partial Output"))
        XCTAssertFalse(report.markdown.contains("very noisy compiler log"))
    }

    private func outputDirectory() throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("proof/pr-77", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func writeFixtureArtifacts(in output: URL) throws {
        for path in ["before/home.png", "after/home.png", "before/flow.mov", "after/flow.mov"] {
            let url = output.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
    }

    private func comparisonPlan() -> PRChangeEvidencePlan {
        PRChangeEvidencePlan(
            repo: "ExampleOrg/ExampleApp",
            pr: 77,
            platform: .ios,
            runner: .simctl,
            ios: PRChangeEvidenceIOSSettings(bundleID: "com.example.app", simulatorUDID: "SIM-123"),
            steps: [
                PRChangeEvidenceStep(name: "Launch app", kind: .launch),
                PRChangeEvidenceStep(name: "Home screen", kind: .screenshot, path: "home.png"),
                PRChangeEvidenceStep(name: "Start flow", kind: .startVideo, path: "flow.mov"),
                PRChangeEvidenceStep(name: "Stop flow", kind: .stopVideo, path: "flow.mov")
            ]
        )
    }

    private func successfulManifest(output: URL) -> PRChangeEvidenceManifest {
        PRChangeEvidenceManifest(
            prNumber: 77,
            prURL: "https://github.com/ExampleOrg/ExampleApp/pull/77",
            prTitle: "Render evidence",
            prState: "OPEN",
            beforeSHA: "1111111111111111111111111111111111111111",
            afterSHA: "2222222222222222222222222222222222222222",
            base: PRRevisionMetadata(repo: "ExampleOrg/ExampleApp", ref: "main", sha: "1111111111111111111111111111111111111111"),
            head: PRRevisionMetadata(repo: "ExampleOrg/ExampleApp", ref: "feature/report", sha: "2222222222222222222222222222222222222222"),
            planPath: ".evidence/pr-home.json",
            command: ["evidence", "capture-pr", "--repo", "ExampleOrg/ExampleApp", "--pr", "77"],
            runnerMode: .simctl,
            simulator: PRChangeEvidenceSimulator(name: "iPhone 17 Pro", udid: "SIM-123"),
            xcodeDestination: "platform=iOS Simulator,id=SIM-123",
            buildResult: PRChangeEvidenceBuildResult(status: .succeeded, logPath: output.appendingPathComponent("logs").path, durationSeconds: 40),
            artifacts: [
                CapturedArtifact(kind: .screenshot, phase: .before, path: output.appendingPathComponent("before/home.png").path, stepName: "Home screen", mediaType: "image/png", fileSize: 12),
                CapturedArtifact(kind: .screenshot, phase: .after, path: output.appendingPathComponent("after/home.png").path, stepName: "Home screen", mediaType: "image/png", fileSize: 11),
                CapturedArtifact(kind: .video, phase: .before, path: output.appendingPathComponent("before/flow.mov").path, stepName: "Stop flow", mediaType: "video/quicktime", fileSize: 24),
                CapturedArtifact(kind: .video, phase: .after, path: output.appendingPathComponent("after/flow.mov").path, stepName: "Stop flow", mediaType: "video/quicktime", fileSize: 25),
                CapturedArtifact(kind: .manifest, path: output.appendingPathComponent("manifest.json").path)
            ],
            stepResults: [
                CaptureStepResult(phase: .before, stepName: "Home screen", kind: .screenshot, status: .succeeded, artifactPath: output.appendingPathComponent("before/home.png").path, startedAt: "2026-05-18T00:00:10Z", completedAt: "2026-05-18T00:00:11Z"),
                CaptureStepResult(phase: .after, stepName: "Home screen", kind: .screenshot, status: .succeeded, artifactPath: output.appendingPathComponent("after/home.png").path, startedAt: "2026-05-18T00:01:10Z", completedAt: "2026-05-18T00:01:11Z")
            ],
            startedAt: "2026-05-18T00:00:00Z",
            completedAt: "2026-05-18T00:02:00Z"
        )
    }
}

private final class RecordingComparisonImageRenderer: ComparisonImageRendering {
    private(set) var requests: [ComparisonImageRenderRequest] = []

    func render(_ request: ComparisonImageRenderRequest) throws -> ComparisonImageRenderResult {
        requests.append(request)
        return .rendered(request.outputURL)
    }
}

private struct SkippingComparisonImageRenderer: ComparisonImageRendering {
    var reason: String

    func render(_ request: ComparisonImageRenderRequest) throws -> ComparisonImageRenderResult {
        .skipped(reason)
    }
}
