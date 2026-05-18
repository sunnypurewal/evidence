import Foundation
import XCTest

/// Metadata for a screenshot captured while running an external Evidence plan.
public struct EvidenceCaptureOutput: Equatable {
    public var stepName: String
    public var url: URL
    public var revisionRole: String?

    public init(stepName: String, url: URL, revisionRole: String? = nil) {
        self.stepName = stepName
        self.url = url
        self.revisionRole = revisionRole
    }
}

/// Loads and executes the XCTest-supported subset of a PR Evidence JSON plan.
public enum EvidencePlanRunner {
    public static let planPathEnvironmentKey = "EVIDENCE_PLAN_PATH"
    public static let outputDirectoryEnvironmentKey = "EVIDENCE_OUTPUT_DIR"
    public static let revisionRoleEnvironmentKey = "EVIDENCE_REVISION_ROLE"

    @discardableResult
    public static func runFromEnvironment(
        on app: XCUIApplication = XCUIApplication(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> [EvidenceCaptureOutput] {
        try runFromEnvironment(on: app as EvidenceApplication, environment: environment, arguments: arguments)
    }

    @discardableResult
    public static func runFromEnvironment(
        on app: EvidenceApplication,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> [EvidenceCaptureOutput] {
        let planPath = try planPath(from: environment, arguments: arguments)
        return try run(planPath: planPath, on: app, environment: environment)
    }

    @discardableResult
    public static func run(
        planPath: String,
        on app: XCUIApplication = XCUIApplication(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [EvidenceCaptureOutput] {
        try run(planPath: planPath, on: app as EvidenceApplication, environment: environment)
    }

    @discardableResult
    public static func run(
        planPath: String,
        on app: EvidenceApplication,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [EvidenceCaptureOutput] {
        let url = URL(fileURLWithPath: planPath)
        let plan = try EvidencePlanDocument.load(from: url)
        return try execute(plan: plan, planPath: url.path, on: app, environment: environment)
    }

    private static func execute(
        plan: EvidencePlanDocument,
        planPath: String,
        on app: EvidenceApplication,
        environment: [String: String]
    ) throws -> [EvidenceCaptureOutput] {
        guard plan.runner == nil || plan.runner == "xctest" else {
            throw EvidenceError.planLoadingFailed(
                path: planPath,
                message: "runner '\(plan.runner ?? "")' is not supported by EvidencePlanRunner; use runner 'xctest'."
            )
        }

        var app = app
        var didApplyLaunchHook = false
        var didLaunch = false
        let revisionRole = normalizedRevisionRole(from: environment)
        let outputDirectory = resolvedOutputDirectory(for: plan, environment: environment)
        var captures: [EvidenceCaptureOutput] = []

        func launchApp() {
            if !didApplyLaunchHook {
                app.apply(plan.launchHook)
                didApplyLaunchHook = true
            }
            app.launch()
            didLaunch = true
        }

        func launchIfNeeded() {
            if !didLaunch {
                launchApp()
            }
        }

        for step in plan.stepsForRevisionRole(revisionRole) {
            guard let kind = EvidencePlanStepKind(rawValue: step.kind) else {
                throw EvidenceError.unsupportedPlanStep(
                    step: step.name,
                    kind: step.kind,
                    reason: "XCTest runner does not support this step kind."
                )
            }

            switch kind {
            case .launch:
                launchApp()
            case .wait:
                launchIfNeeded()
                try wait(for: step, in: app)
            case .screenshot:
                launchIfNeeded()
                let url = try screenshotURL(for: step, outputDirectory: outputDirectory, revisionRole: revisionRole)
                try app.captureScreenshot().write(to: url)
                captures.append(EvidenceCaptureOutput(stepName: step.name, url: url, revisionRole: revisionRole))
            case .openURL:
                launchIfNeeded()
                guard let rawURL = step.url,
                      let url = URL(string: rawURL),
                      url.scheme != nil else {
                    throw unsupported(step, reason: "openURL steps require a valid 'url'.")
                }
                try NavigationAction.openURL(url).perform(in: app)
            case .tap:
                launchIfNeeded()
                guard let label = step.target?.actionLabel else {
                    throw unsupported(step, reason: "tap steps require an accessibility target.")
                }
                try NavigationAction.tapElement(label: label).perform(in: app)
            case .typeText:
                launchIfNeeded()
                guard let label = step.target?.actionLabel else {
                    throw unsupported(step, reason: "typeText steps require an accessibility target.")
                }
                guard let text = step.text, !text.isEmpty else {
                    throw unsupported(step, reason: "typeText steps require non-empty 'text'.")
                }
                try NavigationAction.typeText(label: label, text: text).perform(in: app)
            case .swipe:
                launchIfNeeded()
                guard let rawDirection = step.direction,
                      let direction = NavigationAction.SwipeDirection(rawValue: rawDirection) else {
                    throw unsupported(step, reason: "swipe steps require direction up, down, left, or right.")
                }
                try NavigationAction.swipe(direction: direction).perform(in: app)
            case .startVideo, .stopVideo:
                throw unsupported(
                    step,
                    reason: "Video recording steps are handled by CLI orchestration, not the app-side XCTest runner."
                )
            }
        }

        return captures
    }

    private static func wait(for step: EvidencePlanStep, in app: EvidenceApplication) throws {
        guard let anchor = step.target?.anchor else {
            if let seconds = step.seconds {
                Thread.sleep(forTimeInterval: seconds)
                return
            }
            throw unsupported(step, reason: "wait steps require a target or seconds.")
        }

        let timeout = step.timeoutSeconds ?? 10
        guard anchor.wait(in: app, timeout: timeout) else {
            throw EvidenceError.anchorTimedOut(scene: step.name, anchor: anchor.description, timeout: timeout)
        }
    }

    private static func screenshotURL(
        for step: EvidencePlanStep,
        outputDirectory: URL,
        revisionRole: String?
    ) throws -> URL {
        let fallback = "\(ScreenshotPlan.Scene.fileSafeName(for: step.name)).png"
        var components = try relativePathComponents(from: step.path, fallback: fallback)

        if let revisionRole,
           outputDirectory.lastPathComponent != revisionRole,
           components.first != revisionRole {
            components.insert(revisionRole, at: 0)
        }

        return components.reduce(outputDirectory) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private static func relativePathComponents(from path: String?, fallback: String) throws -> [String] {
        let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativePath = rawPath?.isEmpty == false ? rawPath! : fallback
        guard !relativePath.hasPrefix("/") else {
            throw EvidenceError.navigationFailed("Screenshot path '\(relativePath)' must be relative.")
        }

        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains("..") else {
            throw EvidenceError.navigationFailed("Screenshot path '\(relativePath)' must stay inside the output directory.")
        }
        return components
    }

    private static func resolvedOutputDirectory(
        for plan: EvidencePlanDocument,
        environment: [String: String]
    ) -> URL {
        OutputDirectory(
            environment: environment,
            fallbackURL: URL(fileURLWithPath: plan.outputDirectory, isDirectory: true)
        ).resolvedURL
    }

    private static func normalizedRevisionRole(from environment: [String: String]) -> String? {
        let role = environment[revisionRoleEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return role?.isEmpty == false ? role : nil
    }

    private static func planPath(from environment: [String: String], arguments: [String]) throws -> String {
        if let path = environment[planPathEnvironmentKey], !path.isEmpty {
            return path
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--evidence-plan", arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix("--evidence-plan=") {
                return String(argument.dropFirst("--evidence-plan=".count))
            }
        }

        throw EvidenceError.planLoadingFailed(
            path: "environment",
            message: "missing evidence plan path; set \(planPathEnvironmentKey) or pass --evidence-plan <path>."
        )
    }

    private static func unsupported(_ step: EvidencePlanStep, reason: String) -> EvidenceError {
        EvidenceError.unsupportedPlanStep(step: step.name, kind: step.kind, reason: reason)
    }
}

private enum EvidencePlanStepKind: String {
    case launch
    case wait
    case screenshot
    case startVideo
    case stopVideo
    case openURL
    case tap
    case typeText
    case swipe
}

private struct EvidencePlanDocument: Decodable {
    var runner: String?
    var launchHook: LaunchHook
    var outputDirectory: String
    var steps: [EvidencePlanStep]

    static func load(from url: URL) throws -> EvidencePlanDocument {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(EvidencePlanDocument.self, from: data)
        } catch let error as DecodingError {
            throw EvidenceError.planLoadingFailed(path: url.path, message: decodeMessage(for: error))
        } catch {
            throw EvidenceError.planLoadingFailed(path: url.path, message: error.localizedDescription)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.runner = try container.decodeIfPresent(String.self, forKey: .runner)
        self.launchHook = try container.decodeIfPresent(EvidencePlanLaunch.self, forKey: .launch)?.launchHook ?? .none
        self.outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? "docs/pr-change-evidence"
        self.steps = try container.decode([EvidencePlanStep].self, forKey: .steps)
    }

    func stepsForRevisionRole(_ revisionRole: String?) -> [EvidencePlanStep] {
        guard let revisionRole else { return steps }
        return steps.filter { step in
            step.phase == nil || step.phase == revisionRole
        }
    }

    private enum CodingKeys: String, CodingKey {
        case runner
        case launch
        case outputDirectory = "output_directory"
        case steps
    }

    private static func decodeMessage(for error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "missing required field '\(fieldPath(context.codingPath, appending: key))'"
        case let .typeMismatch(type, context):
            return "invalid field '\(fieldPath(context.codingPath))': expected \(type)"
        case let .valueNotFound(type, context):
            return "missing value for field '\(fieldPath(context.codingPath))': expected \(type)"
        case let .dataCorrupted(context):
            return "invalid field '\(fieldPath(context.codingPath))': \(context.debugDescription)"
        @unknown default:
            return "could not decode plan"
        }
    }

    private static func fieldPath(_ codingPath: [CodingKey], appending key: CodingKey? = nil) -> String {
        let fullPath = key.map { codingPath + [$0] } ?? codingPath
        guard !fullPath.isEmpty else { return "root" }

        return fullPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else if result.isEmpty {
                result = key.stringValue
            } else {
                result += ".\(key.stringValue)"
            }
        }
    }
}

private struct EvidencePlanLaunch: Decodable {
    var arguments: [String]
    var environment: [String: String]

    var launchHook: LaunchHook {
        LaunchHook(launchArguments: arguments, launchEnvironment: environment)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        self.environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case arguments
        case environment
    }
}

private struct EvidencePlanStep: Decodable, Equatable {
    var name: String
    var kind: String
    var phase: String?
    var target: EvidencePlanTarget?
    var timeoutSeconds: TimeInterval?
    var seconds: TimeInterval?
    var path: String?
    var url: String?
    var text: String?
    var direction: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case phase
        case target
        case timeoutSeconds = "timeout_seconds"
        case seconds
        case path
        case url
        case text
        case direction
    }
}

private struct EvidencePlanTarget: Decodable, Equatable {
    var accessibilityLabel: String?
    var staticText: String?
    var button: String?
    var textField: String?
    var predicate: String?

    var actionLabel: String? {
        [accessibilityLabel, button, textField, staticText].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    var anchor: PlanAnchor? {
        if let staticText = nonEmpty(staticText) {
            return .staticText(staticText)
        }
        if let button = nonEmpty(button) {
            return .button(button)
        }
        if let predicate = nonEmpty(predicate) {
            return .predicate(format: predicate)
        }
        if let label = nonEmpty(accessibilityLabel) ?? nonEmpty(textField) {
            return .predicate(format: NSPredicate(format: "label == %@", label).predicateFormat)
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
