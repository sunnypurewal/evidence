import EvidenceCLIKit
import Foundation
import XCTest

final class PRChangeEvidenceContractsTests: XCTestCase {
    func testPlanLoadsMultiSceneBeforeAfterFixture() throws {
        let plan = try PRChangeEvidencePlan.load(from: fixtureURL("pr-change-evidence-plan.json"))

        XCTAssertEqual(plan.repo, "ExampleOrg/ExampleApp")
        XCTAssertEqual(plan.pr, 479)
        XCTAssertEqual(plan.beforeRef, PRRevisionRef(value: "main"))
        XCTAssertEqual(plan.afterRef, PRRevisionRef(kind: .sha, value: "abc1234"))
        XCTAssertEqual(plan.platform, .ios)
        XCTAssertEqual(plan.runner, .xctest)
        XCTAssertEqual(plan.ios?.project, "ios/ExampleApp.xcodeproj")
        XCTAssertEqual(plan.ios?.scheme, "ExampleApp")
        XCTAssertEqual(plan.ios?.bundleID, "com.example.app")
        XCTAssertEqual(plan.ios?.simulator, "iPhone 17 Pro")
        XCTAssertEqual(plan.ios?.destination, "platform=iOS Simulator,name=iPhone 17 Pro")
        XCTAssertEqual(plan.launch.arguments, ["--evidence-mode", "-UIAnimationsDisabled", "YES"])
        XCTAssertEqual(plan.launch.environment, ["EXAMPLE_EVIDENCE_MODE": "1"])
        XCTAssertEqual(plan.outputDirectory, "docs/pr-evidence/EVI-1")
        XCTAssertEqual(plan.video, PRChangeEvidenceVideo(enabled: true, name: "home-flow"))
        XCTAssertEqual(plan.steps.map(\.kind), [.launch, .wait, .screenshot, .tap, .startVideo, .openURL, .typeText, .swipe, .screenshot, .stopVideo])
        XCTAssertEqual(plan.steps[1].target?.staticText, "Home")
        XCTAssertEqual(plan.steps[1].timeoutSeconds, 12)
        XCTAssertEqual(plan.steps[2].path, "before/home.png")
        XCTAssertEqual(plan.steps[3].target?.accessibilityLabel, "Cabinet 1")
        XCTAssertEqual(plan.steps[6].text, "hinge")
        XCTAssertEqual(plan.steps[7].direction, .up)
    }

    func testPlanLoadNamesMissingRequiredFieldsAndPlanPath() throws {
        let url = try writePlan("""
        {
          "pr": 479,
          "platform": "ios",
          "steps": [
            { "name": "launch", "kind": "launch" }
          ]
        }
        """)

        XCTAssertThrowsError(try PRChangeEvidencePlan.load(from: url)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains(url.path), "expected plan path in error: \(message)")
            XCTAssertTrue(message.contains("missing required field 'repo'"), "expected missing field in error: \(message)")
        }
    }

    func testPlanLoadNamesUnsupportedStepKindsAndPlanPath() throws {
        let url = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "platform": "ios",
          "steps": [
            { "name": "pinch image", "kind": "pinch" }
          ]
        }
        """)

        XCTAssertThrowsError(try PRChangeEvidencePlan.load(from: url)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains(url.path), "expected plan path in error: \(message)")
            XCTAssertTrue(message.contains("unsupported step kind 'pinch'"), "expected unsupported kind in error: \(message)")
            XCTAssertTrue(message.contains("steps[0].kind"), "expected coding path in error: \(message)")
        }
    }

    func testPlanDefaultsRunnerLaunchOutputDirectoryAndVideo() throws {
        let url = try writePlan("""
        {
          "repo": "RiddimSoftware/evidence",
          "pr": 1,
          "platform": "ios",
          "ios": {
            "scheme": "EvidenceExample",
            "bundle_id": "com.example.evidence"
          },
          "steps": [
            { "name": "launch", "kind": "launch" },
            { "name": "wait", "kind": "wait", "seconds": 1 },
            { "name": "screenshot", "kind": "screenshot", "path": "home.png" }
          ]
        }
        """)

        let plan = try PRChangeEvidencePlan.load(from: url)

        XCTAssertEqual(plan.runner, .xctest)
        XCTAssertEqual(plan.launch, PRChangeEvidenceLaunch())
        XCTAssertEqual(plan.outputDirectory, "docs/pr-change-evidence")
        XCTAssertEqual(plan.video, PRChangeEvidenceVideo())
        XCTAssertEqual(plan.steps[1].seconds, 1)
    }

    func testPlanParsesIOSBuildAliasesAndSimulatorStateOptions() throws {
        let url = try writePlan("""
        {
          "repo": "RiddimSoftware/evidence",
          "pr": 2,
          "platform": "ios",
          "ios": {
            "xcode_workspace": "ios/AliasApp.xcworkspace",
            "scheme": "AliasApp",
            "bundle_id": "com.example.alias",
            "simulator_udid": "SIM-ALIAS",
            "extra_xcodebuild_arguments": ["CODE_SIGNING_ALLOWED=NO"],
            "preserve_simulator_state": true
          },
          "steps": [
            { "name": "launch", "kind": "launch" }
          ]
        }
        """)

        let plan = try PRChangeEvidencePlan.load(from: url)

        XCTAssertEqual(plan.ios?.workspace, "ios/AliasApp.xcworkspace")
        XCTAssertEqual(plan.ios?.extraBuildArguments, ["CODE_SIGNING_ALLOWED=NO"])
        XCTAssertEqual(plan.ios?.preserveSimulatorState, true)
    }

    func testRunnerCapabilitiesAreExplicitAndValidated() throws {
        XCTAssertTrue(PRChangeEvidenceStep.Kind.tap.supportedRunners.contains(.xctest))
        XCTAssertFalse(PRChangeEvidenceStep.Kind.tap.supportedRunners.contains(.simctl))
        XCTAssertEqual(PRChangeEvidenceStep.Kind.screenshot.supportedRunners, [.xctest, .simctl])

        let url = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "platform": "ios",
          "runner": "simctl",
          "steps": [
            {
              "name": "tap home",
              "kind": "tap",
              "target": { "accessibilityLabel": "Home" }
            }
          ]
        }
        """)

        XCTAssertThrowsError(try PRChangeEvidencePlan.load(from: url)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains(url.path), "expected plan path in error: \(message)")
            XCTAssertTrue(message.contains("steps[0].kind"), "expected step field in error: \(message)")
            XCTAssertTrue(message.contains("runner 'simctl' does not support step kind 'tap'"), "expected capability error: \(message)")
        }
    }

    func testSimctlWaitRejectsAccessibilityTargets() throws {
        let url = try writePlan("""
        {
          "repo": "ExampleOrg/ExampleApp",
          "pr": 479,
          "platform": "ios",
          "runner": "simctl",
          "steps": [
            {
              "name": "wait for home label",
              "kind": "wait",
              "target": { "staticText": "Home" }
            }
          ]
        }
        """)

        XCTAssertThrowsError(try PRChangeEvidencePlan.load(from: url)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains(url.path), "expected plan path in error: \(message)")
            XCTAssertTrue(message.contains("steps[0].target"), "expected target field in error: \(message)")
            XCTAssertTrue(message.contains("simctl wait steps cannot use accessibility targets"), "expected simctl target error: \(message)")
            XCTAssertTrue(message.contains("seconds"), "expected time-based wait guidance: \(message)")
        }
    }

    func testManifestEncodesStableSnakeCaseContract() throws {
        let manifest = PRChangeEvidenceManifest(
            prNumber: 479,
            prURL: "https://github.com/ExampleOrg/ExampleApp/pull/479",
            beforeSHA: "1111111",
            afterSHA: "2222222",
            base: PRRevisionMetadata(repo: "ExampleOrg/ExampleApp", ref: "main", sha: "1111111"),
            head: PRRevisionMetadata(repo: "ExampleOrg/ExampleApp", ref: "feature", sha: "2222222"),
            merge: PRRevisionMetadata(repo: "ExampleOrg/ExampleApp", ref: "refs/pull/479/merge", sha: "3333333"),
            planPath: "evidence/pr-plan.json",
            command: ["evidence", "pr-change", "--plan", "evidence/pr-plan.json"],
            runnerMode: .xctest,
            simulator: PRChangeEvidenceSimulator(name: "iPhone 17 Pro", udid: "SIM-123"),
            xcodeDestination: "platform=iOS Simulator,name=iPhone 17 Pro",
            buildResult: PRChangeEvidenceBuildResult(status: .succeeded, logPath: "logs/build.log", durationSeconds: 42),
            artifacts: [
                CapturedArtifact(kind: .screenshot, phase: .before, path: "before/home.png", stepName: "capture before home", sha256: "abc"),
                CapturedArtifact(kind: .video, phase: .after, path: "after/home-flow.mov", stepName: "stop after video", sha256: nil)
            ],
            startedAt: "2026-05-18T00:00:00Z",
            completedAt: "2026-05-18T00:01:00Z",
            failures: [
                PRChangeEvidenceFailureSummary(stepName: "capture after home", message: "anchor timed out", artifactPath: "after/home.png")
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["pr_number"] as? Int, 479)
        XCTAssertEqual(object["pr_url"] as? String, "https://github.com/ExampleOrg/ExampleApp/pull/479")
        XCTAssertEqual(object["before_sha"] as? String, "1111111")
        XCTAssertEqual(object["after_sha"] as? String, "2222222")
        XCTAssertEqual(object["plan_path"] as? String, "evidence/pr-plan.json")
        XCTAssertEqual(object["command"] as? [String], ["evidence", "pr-change", "--plan", "evidence/pr-plan.json"])
        XCTAssertEqual(object["runner_mode"] as? String, "xctest")
        XCTAssertEqual(object["xcode_destination"] as? String, "platform=iOS Simulator,name=iPhone 17 Pro")
        XCTAssertEqual(object["started_at"] as? String, "2026-05-18T00:00:00Z")
        XCTAssertEqual(object["completed_at"] as? String, "2026-05-18T00:01:00Z")

        let buildResult = try XCTUnwrap(object["build_result"] as? [String: Any])
        XCTAssertEqual(buildResult["status"] as? String, "succeeded")
        XCTAssertEqual(buildResult["log_path"] as? String, "logs/build.log")

        let artifacts = try XCTUnwrap(object["artifacts"] as? [[String: Any]])
        XCTAssertEqual(artifacts.count, 2)
        XCTAssertEqual(artifacts[0]["kind"] as? String, "screenshot")
        XCTAssertEqual(artifacts[0]["phase"] as? String, "before")
        XCTAssertEqual(artifacts[0]["path"] as? String, "before/home.png")

        let decoded = try JSONDecoder().decode(PRChangeEvidenceManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func writePlan(_ json: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("plan.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
