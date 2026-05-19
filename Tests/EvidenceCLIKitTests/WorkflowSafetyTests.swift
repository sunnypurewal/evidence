import Foundation
import XCTest

final class WorkflowSafetyTests: XCTestCase {
    func testPullRequestWorkflowsUsePublicSafeRunners() throws {
        for workflow in try workflowFiles(includingExamples: true) {
            let source = try String(contentsOf: workflow, encoding: .utf8)
            guard source.contains("pull_request:") else {
                continue
            }

            let restrictedRunnerLabel = ["self", "hosted"].joined(separator: "-")
            XCTAssertFalse(
                source.contains(restrictedRunnerLabel),
                "\(relativePath(workflow)) runs pull_request jobs on an organization-owned runner."
            )
        }
    }

    func testActiveRepositoryWorkflowsDoNotDependOnInternalAutomergeBot() throws {
        for workflow in try workflowFiles(includingExamples: false) {
            let source = try String(contentsOf: workflow, encoding: .utf8)

            let botPrefix = ["DEV", "BOT"].joined(separator: "_")
            for internalReference in [
                "\(botPrefix)_APP_ID",
                "\(botPrefix)_\(["PRIVATE", "KEY"].joined(separator: "_"))",
                "actions/create-github-app-token",
                "gh pr merge --auto",
            ] {
                XCTAssertFalse(
                    source.contains(internalReference),
                    "\(relativePath(workflow)) references internal automerge bot infrastructure."
                )
            }
        }
    }

    func testActionManifestDoesNotAdvertiseUnsupportedSubcommands() throws {
        let actionURL = repositoryRoot().appendingPathComponent("action.yml")
        let source = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertFalse(source.contains("diff"), "action.yml must not advertise a removed diff subcommand.")
        XCTAssertFalse(
            source.contains("accept-baseline"),
            "action.yml must not advertise a removed accept-baseline subcommand."
        )
    }

    private func workflowFiles(includingExamples: Bool) throws -> [URL] {
        let root = repositoryRoot()
        var directories = [root.appendingPathComponent(".github/workflows")]
        if includingExamples {
            directories.append(root.appendingPathComponent("Examples/workflows"))
        }

        return try directories.flatMap { directory in
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }
        }
        .sorted { $0.path < $1.path }
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }

    private func relativePath(_ url: URL) -> String {
        let root = repositoryRoot().path + "/"
        return url.path.replacingOccurrences(of: root, with: "")
    }
}
