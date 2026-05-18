import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testArchitectureCatalogDocumentsPREvidenceUseCases() throws {
        let catalog = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("docs/architecture/use-case-catalog.md"),
            encoding: .utf8
        )

        let expectedUseCases = [
            "CapturePullRequestEvidence",
            "ResolvePullRequestComparison",
            "PrepareComparisonWorktrees",
            "BuildRevisionForEvidence",
            "ExecuteEvidencePlan",
            "RenderPullRequestEvidenceReport"
        ]
        let requiredFields = [
            "Actor:",
            "Goal:",
            "Inputs:",
            "Outputs:",
            "Entities / values:",
            "Ports:",
            "Primary adapters:",
            "Current implementation:"
        ]

        for useCase in expectedUseCases {
            guard let entry = markdownSection(named: useCase, in: catalog) else {
                return XCTFail("docs/architecture/use-case-catalog.md must document \(useCase) for the PR evidence architecture catalog.")
            }

            for field in requiredFields {
                XCTAssertTrue(
                    entry.contains(field),
                    "\(useCase) is missing '\(field)' in docs/architecture/use-case-catalog.md."
                )
            }
        }
    }

    func testCapturePRPolicyDoesNotLiveInCLICommandRouter() throws {
        let cliSource = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/EvidenceCLIKit/EvidenceCLI.swift"),
            encoding: .utf8
        )

        let routerBranch = try XCTUnwrap(
            capturePRRouterBranch(in: cliSource),
            """
            Architecture test could not locate capture-pr routing in EvidenceCLI.swift. \
            Keep this scanner aligned with the real command router so capture-pr policy cannot bypass the boundary guard.
            """
        )
        let dispatchBoundary = try XCTUnwrap(
            functionBody(named: "capturePullRequest", in: cliSource),
            """
            Architecture test could not locate capturePullRequest in EvidenceCLI.swift. \
            capture-pr must route through a named dispatch boundary before invoking PR evidence use cases.
            """
        )

        let routerPolicyMarkers = [
            "GitCLIRepositoryPreparer",
            "GitHubCLIPullRequestMetadataProvider",
            "CapturePullRequestEvidence(",
            "ResolvePullRequestComparison",
            "PrepareComparisonWorktrees",
            "runner.run(",
            "Process(",
            "xcodebuild",
            "simctl",
            "xcresulttool"
        ]
        let routerOffenders = routerPolicyMarkers.filter { routerBranch.contains($0) }

        XCTAssertTrue(
            routerOffenders.isEmpty,
            """
            EvidenceCLI.swift must only parse and dispatch the capture-pr command. \
            PR evidence orchestration policy belongs in named use-case/application files documented in \
            docs/architecture/use-case-catalog.md, behind ports for git, GitHub, Xcode, simulator, and filesystem work. \
            Move these policy details out of the CLI router: \(routerOffenders.joined(separator: ", ")).
            """
        )

        let rawDetailMarkers = [
            "runner.run(",
            "Process(",
            "\"worktree\"",
            "\"checkout\"",
            "\"pr\", \"view\"",
            "api.github.com",
            "GITHUB_",
            "pull_request",
            "xcodebuild",
            "simctl",
            "xcresulttool"
        ]
        let dispatchOffenders = rawDetailMarkers.filter {
            dispatchBoundary.range(of: $0, options: [.caseInsensitive]) != nil
        }

        XCTAssertTrue(
            dispatchOffenders.isEmpty,
            """
            capturePullRequest in EvidenceCLI.swift must remain a thin dispatch boundary. \
            Raw Git, GitHub, Xcode, simulator, and filesystem policy belongs in named use-case/application files \
            documented in docs/architecture/use-case-catalog.md and behind ports/adapters. \
            Move these policy details out of the CLI dispatch boundary: \(dispatchOffenders.joined(separator: ", ")).
            """
        )
    }

    func testPREvidenceValueObjectsDoNotImportFrameworkOrProcessDetails() throws {
        let root = try packageRoot()
        let valueObjectFiles = Set([
            "Sources/EvidenceCLIKit/PRChangeEvidenceContracts.swift",
            "Sources/EvidenceCLIKit/PullRequestComparison.swift"
        ])
        let candidateFiles = try swiftFiles(under: root.appendingPathComponent("Sources"))
            .filter { url in
                let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
                let path = url.path
                let name = url.deletingPathExtension().lastPathComponent
                return valueObjectFiles.contains(relativePath)
                    || path.contains("/PullRequestEvidence/")
                    || path.contains("/PREvidence/")
                    || name.contains("PullRequest")
                    || name.contains("Comparison")
                    || name.contains("EvidenceRevision")
                    || name.contains("EvidenceReport")
            }
        XCTAssertTrue(
            candidateFiles.contains { $0.lastPathComponent == "PRChangeEvidenceContracts.swift" },
            "PR evidence value-object boundary coverage must include PRChangeEvidenceContracts.swift."
        )

        let bannedImports = [
            "XCTest",
            "GitHub",
            "XcodeProj"
        ]
        let bannedTerms = [
            "XCUIApplication",
            "Process()",
            "ProcessCommandRunner",
            "\"simctl\"",
            "Simctl",
            "xcodebuild",
            "xcresulttool",
            "gh pr",
            "api.github.com"
        ]

        var failures: [String] = []
        for file in candidateFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let importOffenders = bannedImports.filter { source.contains("import \($0)") }
            let termOffenders = bannedTerms.filter { source.contains($0) }
            if !importOffenders.isEmpty || !termOffenders.isEmpty {
                let relativePath = file.path.replacingOccurrences(of: root.path + "/", with: "")
                failures.append("\(relativePath): \(importOffenders + termOffenders)")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            """
            PR evidence value objects must stay framework- and process-free. \
            Keep XCTest, GitHub API, Xcode process, and simctl details in adapters behind ports. \
            Offending files: \(failures.joined(separator: "; "))
            """
        )
    }

    func testEvidenceLibraryTargetDoesNotImportEvidenceCLIKit() throws {
        let root = try packageRoot()
        let files = try swiftFiles(under: root.appendingPathComponent("Sources/Evidence"))
        let offenders = try files.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("import EvidenceCLIKit") else {
                return nil
            }
            return file.path.replacingOccurrences(of: root.path + "/", with: "")
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "The Evidence library target must not import EvidenceCLIKit. Keep CLI adapters depending inward on the Evidence library, not the reverse. Offending files: \(offenders.joined(separator: ", "))."
        )
    }

    private func markdownSection(named heading: String, in markdown: String) -> String? {
        let pattern = "### \(heading)"
        guard let start = markdown.range(of: pattern) else {
            return nil
        }
        let tail = markdown[start.lowerBound...]
        let end = tail.range(of: "\n### ", options: [], range: tail.index(after: start.lowerBound)..<tail.endIndex)?.lowerBound ?? tail.endIndex
        return String(tail[..<end])
    }

    private func capturePRRouterBranch(in source: String) -> String? {
        guard let start = source.range(of: "if first == \"capture-pr\" {") else {
            return nil
        }
        let tail = source[start.lowerBound...]
        let end = tail.range(of: "\n\n        let config = try loadConfig()", options: [], range: tail.index(after: start.lowerBound)..<tail.endIndex)?.lowerBound
            ?? tail.endIndex
        return String(tail[..<end])
    }

    private func functionBody(named name: String, in source: String) -> String? {
        guard let start = source.range(of: "private func \(name)") else {
            return nil
        }
        let openBrace = source[start.lowerBound...].firstIndex(of: "{")
        guard let openBrace else {
            return nil
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[start.lowerBound...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private func packageRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate Package.swift from \(#filePath).")
    }
}
