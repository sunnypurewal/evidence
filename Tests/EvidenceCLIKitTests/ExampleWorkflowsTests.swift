import EvidenceCLIKit
import Foundation
import XCTest

/// Validates that the workflow files shipped under `Examples/workflows/` only
/// reference inputs declared in the canonical `action.yml`. Catches drift
/// between the published Action surface and the documented examples.
final class ExampleWorkflowsTests: XCTestCase {
    func testExampleWorkflowsReferenceOnlyDeclaredActionInputs() throws {
        let root = repositoryRoot()
        let actionSource = try String(contentsOf: root.appendingPathComponent("action.yml"), encoding: .utf8)
        let declaredInputs = parseInputNames(from: actionSource)
        XCTAssertFalse(declaredInputs.isEmpty, "Failed to parse declared inputs from action.yml")

        let workflowsDirectory = root.appendingPathComponent("Examples/workflows")
        let files = try FileManager.default.contentsOfDirectory(
            at: workflowsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }
        XCTAssertGreaterThanOrEqual(files.count, 2, "Expected at least two example workflows")

        for file in files {
            let workflow = try String(contentsOf: file, encoding: .utf8)
            let referenced = parseInputReferences(from: workflow)
            for input in referenced {
                XCTAssertTrue(
                    declaredInputs.contains(input),
                    "Example workflow \(file.lastPathComponent) references undeclared action input '\(input)'."
                )
            }
        }
    }

    func testExampleWorkflowsTargetMacOS14() throws {
        let root = repositoryRoot()
        let workflowsDirectory = root.appendingPathComponent("Examples/workflows")
        let files = try FileManager.default.contentsOfDirectory(
            at: workflowsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }

        for file in files {
            let workflow = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(
                workflow.contains("runs-on: macos-14") || workflow.contains("runs-on: macos-15"),
                "Example workflow \(file.lastPathComponent) must run on a supported macOS runner."
            )
        }
    }

    private func parseInputNames(from actionSource: String) -> Set<String> {
        var names: Set<String> = []
        var inInputs = false
        for rawLine in actionSource.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("inputs:") {
                inInputs = true
                continue
            }
            if inInputs {
                // A new top-level key (no leading whitespace) ends the inputs block.
                if let first = line.first, first != " ", first != "\t", first != "#", !line.isEmpty {
                    break
                }
                if line.hasPrefix("  ") && !line.hasPrefix("    ") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let colon = trimmed.firstIndex(of: ":") {
                        names.insert(String(trimmed[..<colon]))
                    }
                }
            }
        }
        return names
    }

    private func parseInputReferences(from workflow: String) -> Set<String> {
        var seen: Set<String> = []
        // Capture keys from `with:` blocks that follow a `uses: RiddimSoftware/evidence...` line.
        // Other actions (e.g. actions/upload-artifact) may declare their own inputs that are
        // unrelated to the evidence action surface.
        let lines = workflow.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var pendingEvidenceUses = false
        var inWithBlock = false
        var withIndent: Int = 0
        for line in lines {
            let leadingSpaces = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("uses:") {
                pendingEvidenceUses = trimmed.contains("RiddimSoftware/evidence")
                inWithBlock = false
                continue
            }

            if pendingEvidenceUses, trimmed == "with:" {
                inWithBlock = true
                withIndent = leadingSpaces
                continue
            }

            if inWithBlock {
                if trimmed.isEmpty {
                    continue
                }
                if leadingSpaces <= withIndent {
                    inWithBlock = false
                    pendingEvidenceUses = false
                    continue
                }
                if let colon = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[..<colon])
                    seen.insert(key)
                }
            }
        }
        return seen
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}
