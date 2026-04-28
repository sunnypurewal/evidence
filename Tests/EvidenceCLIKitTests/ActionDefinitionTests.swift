import EvidenceCLIKit
import Foundation
import XCTest

final class ActionDefinitionTests: XCTestCase {
    func testRepositoryActionYmlSatisfiesRequiredSurface() throws {
        let actionURL = repositoryRoot().appendingPathComponent("action.yml")
        let source = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertNoThrow(try ActionDefinitionValidator().validate(source))
    }

    func testValidatorRejectsActionMissingRequiredInput() {
        let source = """
        name: 'evidence'
        description: 'x'
        branding:
          icon: 'camera'
          color: 'purple'
        inputs:
          subcommand:
            description: 'x'
        outputs:
          output-dir:
            value: ''
          artifact-count:
            value: ''
        runs:
          using: 'composite'
          steps:
            - shell: bash
              run: 'true'
        """

        XCTAssertThrowsError(try ActionDefinitionValidator().validate(source)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("action.yml is missing the required input 'config'.")
            )
        }
    }

    func testValidatorRejectsActionMissingRequiredOutput() {
        var source = "name: 'evidence'\ndescription: 'x'\nbranding:\n  icon: 'camera'\n  color: 'purple'\n"
        source += "inputs:\n"
        for input in ActionDefinitionValidator.defaultRequirements.requiredInputNames {
            source += "  \(input):\n    description: 'x'\n"
        }
        source += "outputs:\n  output-dir:\n    value: ''\n"
        source += "runs:\n  using: 'composite'\n  steps:\n    - shell: bash\n      run: 'true'\n"

        XCTAssertThrowsError(try ActionDefinitionValidator().validate(source)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("action.yml is missing the required output 'artifact-count'.")
            )
        }
    }

    func testValidatorRejectsNonCompositeRunsUsing() {
        var source = "name: 'evidence'\ndescription: 'x'\nbranding:\n  icon: 'camera'\n  color: 'purple'\n"
        source += "inputs:\n"
        for input in ActionDefinitionValidator.defaultRequirements.requiredInputNames {
            source += "  \(input):\n    description: 'x'\n"
        }
        source += "outputs:\n"
        for output in ActionDefinitionValidator.defaultRequirements.requiredOutputNames {
            source += "  \(output):\n    value: ''\n"
        }
        source += "runs:\n  using: 'node20'\n  main: 'index.js'\n"

        XCTAssertThrowsError(try ActionDefinitionValidator().validate(source)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("action.yml runs.using must be 'composite'.")
            )
        }
    }

    private func repositoryRoot() -> URL {
        // Tests are compiled from .build/<config>/EvidenceCLIKitTests.xctest;
        // walking up to the repo root from the source file is reliable.
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // ActionDefinitionTests.swift
        url.deleteLastPathComponent() // EvidenceCLIKitTests
        url.deleteLastPathComponent() // Tests
        return url
    }
}
