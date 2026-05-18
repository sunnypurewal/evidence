import EvidenceCLIKit
import Foundation
import XCTest

final class IOSRevisionAdaptersTests: XCTestCase {
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
            "--repo", "RiddimSoftware/example",
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
            "--repo", "RiddimSoftware/example",
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
            "--repo", "RiddimSoftware/example",
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
            "--repo", "RiddimSoftware/example",
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
            "--repo", "RiddimSoftware/example",
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
        preserveSimulatorState: Bool = false
    ) throws -> URL {
        let planDirectory = directory.appendingPathComponent(".evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: planDirectory, withIntermediateDirectories: true)
        let url = planDirectory.appendingPathComponent("pr-home.json")
        let json = """
        {
          "repo": "RiddimSoftware/example",
          "pr": 44,
          "platform": "ios",
          "runner": "simctl",
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
            { "name": "launch", "kind": "launch" },
            { "name": "settle", "kind": "wait", "seconds": 1 }
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

    private static func pullRequestJSON(baseSHA: String, headSHA: String) -> String {
        """
        {
          "url": "https://github.com/RiddimSoftware/example/pull/44",
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
    private(set) var commands: [Command] = []

    init(
        ghJSON: String,
        resolvedRefs: [String: String],
        xcodebuildStdout: String = "Build Succeeded",
        xcodebuildStderr: String = "",
        xcodebuildExitCodes: [PRChangeEvidencePhase: Int32] = [:],
        simulatorFailureStage: IOSSimulatorFailureStage? = nil
    ) {
        self.ghJSON = ghJSON
        self.resolvedRefs = resolvedRefs
        self.xcodebuildStdout = xcodebuildStdout
        self.xcodebuildStderr = xcodebuildStderr
        self.xcodebuildExitCodes = xcodebuildExitCodes
        self.simulatorFailureStage = simulatorFailureStage
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
        return CommandResult(exitCode: 0)
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
