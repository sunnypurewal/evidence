import EvidenceCLIKit
import Foundation
import XCTest

final class PullRequestComparisonTests: XCTestCase {
    func testCapturePRForMergedPullRequestUsesMergeParentAndWritesManifest() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("docs/evidence/pr-479", isDirectory: true)
        let mergeSHA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let firstParentSHA = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let headSHA = "cccccccccccccccccccccccccccccccccccccccc"
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(
                state: "MERGED",
                baseSHA: "dddddddddddddddddddddddddddddddddddddddd",
                headSHA: headSHA,
                mergeSHA: mergeSHA
            )),
            resolvedRefs: [
                "\(mergeSHA)^1": firstParentSHA,
                "\(mergeSHA)^{commit}": mergeSHA,
                "\(firstParentSHA)^{commit}": firstParentSHA
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "479",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])

        let manifestURL = output.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(
            PRChangeEvidenceManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(manifest.prNumber, 479)
        XCTAssertEqual(manifest.prURL, "https://github.com/RiddimSoftware/epac/pull/479")
        XCTAssertEqual(manifest.prTitle, "Resolve visual evidence")
        XCTAssertEqual(manifest.prState, "MERGED")
        XCTAssertEqual(manifest.base, PRRevisionMetadata(repo: "RiddimSoftware/epac", ref: "main", sha: "dddddddddddddddddddddddddddddddddddddddd"))
        XCTAssertEqual(manifest.head, PRRevisionMetadata(repo: "RiddimSoftware/epac", ref: "feature/evidence", sha: headSHA))
        XCTAssertEqual(manifest.merge, PRRevisionMetadata(repo: "RiddimSoftware/epac", ref: "refs/pull/479/merge", sha: mergeSHA))
        XCTAssertEqual(manifest.beforeSHA, firstParentSHA)
        XCTAssertEqual(manifest.afterSHA, mergeSHA)
        XCTAssertEqual(manifest.worktrees.map(\.label), [.before, .after])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("worktrees/before-\(String(firstParentSHA.prefix(12)))").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("worktrees/after-\(String(mergeSHA.prefix(12)))").path))
        XCTAssertFalse(
            runner.commands.contains { $0.arguments.contains("checkout") || $0.arguments.contains("switch") },
            "capture-pr must not switch the root checkout branch"
        )
    }

    func testCapturePRForOpenPullRequestUsesCurrentBaseAndHeadSHAs() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-12", isDirectory: true)
        let baseSHA = "1111111111111111111111111111111111111111"
        let headSHA = "2222222222222222222222222222222222222222"
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(state: "OPEN", baseSHA: baseSHA, headSHA: headSHA)),
            resolvedRefs: [
                "\(baseSHA)^{commit}": baseSHA,
                "\(headSHA)^{commit}": headSHA
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "12",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])

        let manifest = try JSONDecoder().decode(
            PRChangeEvidenceManifest.self,
            from: Data(contentsOf: output.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(manifest.beforeSHA, baseSHA)
        XCTAssertEqual(manifest.afterSHA, headSHA)
        XCTAssertNil(manifest.merge)
    }

    func testExplicitBeforeAndAfterRefsOverridePullRequestDefaults() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-19", isDirectory: true)
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(
                state: "OPEN",
                baseSHA: "3333333333333333333333333333333333333333",
                headSHA: "4444444444444444444444444444444444444444"
            )),
            resolvedRefs: [
                "release-base^{commit}": "5555555555555555555555555555555555555555",
                "candidate-head^{commit}": "6666666666666666666666666666666666666666",
                "5555555555555555555555555555555555555555^{commit}": "5555555555555555555555555555555555555555",
                "6666666666666666666666666666666666666666^{commit}": "6666666666666666666666666666666666666666"
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "19",
            "--before-ref", "release-base",
            "--after-ref", "candidate-head",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])

        let manifest = try JSONDecoder().decode(
            PRChangeEvidenceManifest.self,
            from: Data(contentsOf: output.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(manifest.beforeRef, "release-base")
        XCTAssertEqual(manifest.afterRef, "candidate-head")
        XCTAssertEqual(manifest.beforeSHA, "5555555555555555555555555555555555555555")
        XCTAssertEqual(manifest.afterSHA, "6666666666666666666666666666666666666666")
    }

    func testCapturePRSurfacesMetadataResolutionFailuresSeparately() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-404", isDirectory: true)
        let runner = PRComparisonRunner(ghResult: .failure("GraphQL: Could not resolve to a PullRequest"))
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "404",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("PR metadata resolution failed"))
            XCTAssertTrue(message.contains("RiddimSoftware/epac#404"))
        }
    }

    func testCapturePRRequiresTheRequestedPlanFileBeforePreparingWorktrees() throws {
        let directory = try temporaryDirectory(writePlan: false)
        let output = directory.appendingPathComponent("proof/pr-missing-plan", isDirectory: true)
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(
                state: "OPEN",
                baseSHA: "1212121212121212121212121212121212121212",
                headSHA: "3434343434343434343434343434343434343434"
            )),
            resolvedRefs: [
                "1212121212121212121212121212121212121212^{commit}": "1212121212121212121212121212121212121212",
                "3434343434343434343434343434343434343434^{commit}": "3434343434343434343434343434343434343434"
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "24",
            "--plan", ".evidence/missing.json",
            "--output", output.path
        ])) { error in
            guard case .config(let message) = (error as? CLIError) else {
                return XCTFail("expected config, got \(error)")
            }
            XCTAssertTrue(message.contains("Missing PR change evidence plan"))
            XCTAssertTrue(message.contains(".evidence/missing.json"))
        }

        XCTAssertTrue(runner.commands.isEmpty, "capture-pr should validate the requested plan before running gh or git commands")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("manifest.json").path))

        let report = output.appendingPathComponent("report.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.path), "capture-pr should write a report-only failure report even when the plan is missing")
        let reportMarkdown = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(reportMarkdown.contains("### Report-Only Partial Output"))
        XCTAssertTrue(reportMarkdown.contains("Missing PR change evidence plan"))
    }

    func testCapturePRSurfacesMissingExplicitRefSeparately() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-20", isDirectory: true)
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(
                state: "OPEN",
                baseSHA: "7777777777777777777777777777777777777777",
                headSHA: "8888888888888888888888888888888888888888"
            )),
            resolvedRefs: [
                "8888888888888888888888888888888888888888^{commit}": "8888888888888888888888888888888888888888"
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "20",
            "--before-ref", "missing-release",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Missing ref 'missing-release'"))
        }
    }

    func testWorktreePreparationRefusesDirtyExistingEvidenceWorktree() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-21", isDirectory: true)
        let sha = "9999999999999999999999999999999999999999"
        let existing = output.appendingPathComponent("worktrees/before-\(String(sha.prefix(12)))", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: output.appendingPathComponent("worktrees/.evidence-owned", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: output.appendingPathComponent("worktrees/.evidence-owned/before-\(String(sha.prefix(12))).json"),
            atomically: true,
            encoding: .utf8
        )
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(state: "OPEN", baseSHA: sha, headSHA: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            resolvedRefs: [
                "\(sha)^{commit}": sha,
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa^{commit}": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ],
            statusByPath: [existing.path: "M Sources/App.swift\n"]
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "21",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Dirty pre-existing worktree"))
        }
    }

    func testWorktreePreparationRefreshesCleanEvidenceOwnedWorktree() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-23", isDirectory: true)
        let baseSHA = "dddddddddddddddddddddddddddddddddddddddd"
        let headSHA = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        let existing = output.appendingPathComponent("worktrees/before-\(String(baseSHA.prefix(12)))", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: output.appendingPathComponent("worktrees/.evidence-owned", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: output.appendingPathComponent("worktrees/.evidence-owned/before-\(String(baseSHA.prefix(12))).json"),
            atomically: true,
            encoding: .utf8
        )
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(state: "OPEN", baseSHA: baseSHA, headSHA: headSHA)),
            resolvedRefs: [
                "\(baseSHA)^{commit}": baseSHA,
                "\(headSHA)^{commit}": headSHA
            ]
        )
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "23",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])

        let worktreeCommands = runner.commands.compactMap { command -> [String]? in
            guard command.executable == "/usr/bin/git", command.arguments.count >= 3 else { return nil }
            return Array(command.arguments.dropFirst(2))
        }
        XCTAssertTrue(worktreeCommands.contains(["worktree", "remove", "--force", existing.path]))
        XCTAssertTrue(worktreeCommands.contains(["worktree", "add", "--detach", existing.path, baseSHA]))
    }

    func testWorktreePreparationSurfacesGitCommandFailuresSeparately() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("proof/pr-22", isDirectory: true)
        let baseSHA = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let headSHA = "cccccccccccccccccccccccccccccccccccccccc"
        let runner = PRComparisonRunner(
            ghResult: .success(Self.pullRequestJSON(state: "OPEN", baseSHA: baseSHA, headSHA: headSHA)),
            resolvedRefs: [
                "\(baseSHA)^{commit}": baseSHA,
                "\(headSHA)^{commit}": headSHA
            ],
            worktreeAddError: "fatal: invalid reference"
        )
        let cli = testCLI(directory: directory, runner: runner)

        XCTAssertThrowsError(try cli.execute([
            "capture-pr",
            "--repo", "RiddimSoftware/epac",
            "--pr", "22",
            "--plan", ".evidence/pr-home.json",
            "--output", output.path
        ])) { error in
            guard case .commandFailed(let message) = (error as? CLIError) else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Git command failed while creating worktree"))
        }

        let reportURL = output.appendingPathComponent("report.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let report = try String(contentsOf: reportURL, encoding: .utf8)
        XCTAssertTrue(report.contains("[#22 Resolve visual evidence](https://github.com/RiddimSoftware/epac/pull/479)"))
        XCTAssertTrue(report.contains("- PR title: Resolve visual evidence"))
        XCTAssertTrue(report.contains("- PR URL: https://github.com/RiddimSoftware/epac/pull/479"))
        XCTAssertTrue(report.contains("- Before SHA: `\(baseSHA)`"))
        XCTAssertTrue(report.contains("- After SHA: `\(headSHA)`"))
        XCTAssertTrue(report.contains("- Runner mode: `simctl`"))
        XCTAssertTrue(report.contains("- Simulator: `SIM-PR`"))
        XCTAssertTrue(report.contains("Git command failed while creating worktree"))
    }

    private func testCLI(directory: URL, runner: PRComparisonRunner) -> EvidenceCLI {
        EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            currentDirectory: directory,
            toolPaths: ToolPaths(
                xcrun: "/bin/echo",
                magick: "/bin/echo",
                ffmpeg: "/bin/echo",
                git: "/usr/bin/git",
                node: "/bin/echo",
                gh: "/usr/bin/gh"
            ),
            clock: FixedEvidenceClock(date: Date(timeIntervalSince1970: 1_714_000_000))
        )
    }

    private func temporaryDirectory(writePlan: Bool = true) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if writePlan {
            try Self.writePlan(in: directory)
        }
        return directory
    }

    private static func writePlan(in directory: URL) throws {
        let planDirectory = directory.appendingPathComponent(".evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: planDirectory, withIntermediateDirectories: true)
        let planURL = planDirectory.appendingPathComponent("pr-home.json")
        let json = """
        {
          "repo": "RiddimSoftware/epac",
          "pr": 1,
          "platform": "ios",
          "runner": "simctl",
          "ios": {
            "project": "App.xcodeproj",
            "scheme": "App",
            "bundle_id": "com.example.app",
            "simulator_udid": "SIM-PR",
            "destination": "platform=iOS Simulator,id=SIM-PR"
          },
          "steps": [
            { "name": "launch", "kind": "launch" }
          ]
        }
        """
        try json.write(to: planURL, atomically: true, encoding: .utf8)
    }

    private static func pullRequestJSON(
        state: String,
        baseSHA: String,
        headSHA: String,
        mergeSHA: String? = nil
    ) -> String {
        var mergeCommit: String
        if let mergeSHA {
            mergeCommit = #""mergeCommit": {"oid": "\#(mergeSHA)"}"#
        } else {
            mergeCommit = #""mergeCommit": null"#
        }
        return """
        {
          "url": "https://github.com/RiddimSoftware/epac/pull/479",
          "title": "Resolve visual evidence",
          "state": "\(state)",
          "baseRefName": "main",
          "headRefName": "feature/evidence",
          "baseRefOid": "\(baseSHA)",
          "headRefOid": "\(headSHA)",
          \(mergeCommit)
        }
        """
    }
}

private struct FixedEvidenceClock: EvidenceClock {
    var date: Date

    func now() -> Date {
        date
    }
}

private final class PRComparisonRunner: CommandRunning {
    enum GHResult {
        case success(String)
        case failure(String)
    }

    struct Command: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let ghResult: GHResult
    private let resolvedRefs: [String: String]
    private let statusByPath: [String: String]
    private let worktreeAddError: String?
    private(set) var commands: [Command] = []

    init(
        ghResult: GHResult,
        resolvedRefs: [String: String] = [:],
        statusByPath: [String: String] = [:],
        worktreeAddError: String? = nil
    ) {
        self.ghResult = ghResult
        self.resolvedRefs = resolvedRefs
        self.statusByPath = statusByPath
        self.worktreeAddError = worktreeAddError
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        commands.append(Command(executable: executable, arguments: arguments))

        if executable == "/usr/bin/gh" {
            switch ghResult {
            case .success(let stdout):
                return CommandResult(exitCode: 0, stdout: stdout)
            case .failure(let stderr):
                return CommandResult(exitCode: 1, stderr: stderr)
            }
        }

        guard executable == "/usr/bin/git" else {
            return CommandResult(exitCode: 0)
        }

        if let command = gitCommand(arguments), command.starts(with: ["fetch"]) {
            return CommandResult(exitCode: 0)
        }

        if let command = gitCommand(arguments), command.starts(with: ["rev-parse", "--verify"]),
           command.count == 3 {
            let ref = command[2]
            if let resolved = resolvedRefs[ref] {
                return CommandResult(exitCode: 0, stdout: "\(resolved)\n")
            }
            return CommandResult(exitCode: 1, stderr: "fatal: needed a single revision\n")
        }

        if arguments.count >= 4,
           arguments[0] == "-C",
           arguments.suffix(2).elementsEqual(["status", "--porcelain"]) {
            return CommandResult(exitCode: 0, stdout: statusByPath[arguments[1]] ?? "")
        }

        if let command = gitCommand(arguments), command.starts(with: ["worktree", "remove"]) {
            if let path = command.last {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
            return CommandResult(exitCode: 0)
        }

        if let command = gitCommand(arguments), command.starts(with: ["worktree", "add"]) {
            if let worktreeAddError {
                return CommandResult(exitCode: 128, stderr: worktreeAddError)
            }
            guard command.count >= 5 else {
                return CommandResult(exitCode: 128, stderr: "missing worktree path")
            }
            let path = command[3]
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
            return CommandResult(exitCode: 0)
        }

        return CommandResult(exitCode: 0)
    }

    private func gitCommand(_ arguments: [String]) -> [String]? {
        guard arguments.count >= 3, arguments[0] == "-C" else {
            return nil
        }
        return Array(arguments.dropFirst(2))
    }
}
