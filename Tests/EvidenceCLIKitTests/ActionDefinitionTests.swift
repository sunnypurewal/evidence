import EvidenceCLIKit
import Foundation
import XCTest

final class ActionDefinitionTests: XCTestCase {
    func testRepositoryActionYmlSatisfiesRequiredSurface() throws {
        let actionURL = repositoryRoot().appendingPathComponent("action.yml")
        let source = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertNoThrow(try ActionDefinitionValidator().validate(source))
    }

    func testRepositoryActionYmlGatesPRCommentOnTokenPresence() throws {
        // RIDDIM-30 acceptance: the PR-comment step must no-op cleanly when
        // the caller hasn't supplied a token. We assert the structural gate
        // in `action.yml` rather than executing the composite action.
        let actionURL = repositoryRoot().appendingPathComponent("action.yml")
        let source = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("inputs.github-token != ''"),
            "PR-comment step in action.yml must be gated on `inputs.github-token != ''` so token-absent runs no-op cleanly."
        )
        XCTAssertTrue(
            source.contains("GITHUB_TOKEN: ${{ inputs.github-token }}"),
            "PR-comment step must read the token from `inputs.github-token`, not from the `secrets` context."
        )
    }

    func testRepositoryActionYmlHasNoSecretsContextReference() throws {
        // Hard regression guard: even a literal `${{ secrets.* }}` inside a
        // description string fails the runner. The validator catches it, but
        // we assert it explicitly so a future contributor sees the rule.
        let actionURL = repositoryRoot().appendingPathComponent("action.yml")
        let source = try String(contentsOf: actionURL, encoding: .utf8)

        let collapsed = source.replacingOccurrences(of: " ", with: "")
        XCTAssertFalse(
            collapsed.contains("${{secrets."),
            "action.yml must not reference `secrets.*` directly; route tokens via `inputs.github-token`."
        )
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

    func testValidatorRejectsSecretsReferenceInDescription() {
        // Reproduces RIDDIM-30: a literal `${{ secrets.GITHUB_TOKEN }}` inside
        // an input description causes the runner to fail with
        // "Unrecognized named-value: 'secrets'" because composite actions do
        // not have access to the `secrets` context. The validator must catch
        // it before the manifest ships.
        var source = "name: 'evidence'\ndescription: 'x'\nbranding:\n  icon: 'camera'\n  color: 'purple'\n"
        source += "inputs:\n"
        for input in ActionDefinitionValidator.defaultRequirements.requiredInputNames {
            if input == "github-token" {
                source += "  github-token:\n    description: 'pass ${{ secrets.GITHUB_TOKEN }} here'\n"
            } else {
                source += "  \(input):\n    description: 'x'\n"
            }
        }
        source += "outputs:\n"
        for output in ActionDefinitionValidator.defaultRequirements.requiredOutputNames {
            source += "  \(output):\n    value: ''\n"
        }
        source += "runs:\n  using: 'composite'\n  steps:\n    - shell: bash\n      run: 'true'\n"

        XCTAssertThrowsError(try ActionDefinitionValidator().validate(source)) { error in
            guard case let .config(message)? = error as? CLIError else {
                XCTFail("Expected CLIError.config, got \(error)")
                return
            }
            XCTAssertTrue(
                message.contains("secrets"),
                "Expected error message to mention 'secrets', got: \(message)"
            )
        }
    }

    func testValidatorRejectsSecretsReferenceWithoutInnerWhitespace() {
        // Cover the no-whitespace form `${{secrets.X}}` so a manifest can't
        // sneak the regression past the validator by tightening expression
        // formatting.
        var source = "name: 'evidence'\ndescription: 'x'\nbranding:\n  icon: 'camera'\n  color: 'purple'\n"
        source += "inputs:\n"
        for input in ActionDefinitionValidator.defaultRequirements.requiredInputNames {
            source += "  \(input):\n    description: 'x'\n"
        }
        source += "outputs:\n"
        for output in ActionDefinitionValidator.defaultRequirements.requiredOutputNames {
            source += "  \(output):\n    value: ''\n"
        }
        source += "runs:\n  using: 'composite'\n  steps:\n    - shell: bash\n      env:\n        TOKEN: ${{secrets.GITHUB_TOKEN}}\n      run: 'true'\n"

        XCTAssertThrowsError(try ActionDefinitionValidator().validate(source))
    }

    func testValidatorAcceptsInputsGithubTokenContextReference() {
        // The token value is allowed to flow through `inputs.github-token`
        // (set by the calling workflow). This should pass the validator.
        var source = "name: 'evidence'\ndescription: 'x'\nbranding:\n  icon: 'camera'\n  color: 'purple'\n"
        source += "inputs:\n"
        for input in ActionDefinitionValidator.defaultRequirements.requiredInputNames {
            source += "  \(input):\n    description: 'x'\n"
        }
        source += "outputs:\n"
        for output in ActionDefinitionValidator.defaultRequirements.requiredOutputNames {
            source += "  \(output):\n    value: ''\n"
        }
        source += "runs:\n  using: 'composite'\n  steps:\n    - shell: bash\n      env:\n        TOKEN: ${{ inputs.github-token }}\n      run: 'true'\n"

        XCTAssertNoThrow(try ActionDefinitionValidator().validate(source))
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
