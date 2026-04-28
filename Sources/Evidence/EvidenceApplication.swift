import Foundation
import XCTest

/// A small abstraction over `XCUIApplication` that keeps plan execution testable.
public protocol EvidenceApplication {
    var launchArguments: [String] { get set }
    var launchEnvironment: [String: String] { get set }

    func launch()
    func waitForStaticText(_ label: String, timeout: TimeInterval) -> Bool
    func waitForButton(_ label: String, timeout: TimeInterval) -> Bool
    func waitForElement(matching predicate: NSPredicate, timeout: TimeInterval) -> Bool
    func tapButton(_ label: String) throws
    func swipeLeft()
    func captureScreenshot() throws -> EvidenceScreenshot
}

public extension EvidenceApplication {
    mutating func apply(_ launchHook: LaunchHook) {
        launchArguments.append(contentsOf: launchHook.launchArguments)
        launchEnvironment.merge(launchHook.launchEnvironment) { _, new in new }
    }
}

/// PNG screenshot data captured from an app run.
public struct EvidenceScreenshot: Equatable {
    public var pngData: Data

    public init(pngData: Data) {
        self.pngData = pngData
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: url, options: .atomic)
    }
}

extension XCUIApplication: EvidenceApplication {
    public func waitForStaticText(_ label: String, timeout: TimeInterval) -> Bool {
        staticTexts[label].waitForExistence(timeout: timeout)
    }

    public func waitForButton(_ label: String, timeout: TimeInterval) -> Bool {
        buttons[label].waitForExistence(timeout: timeout)
    }

    public func waitForElement(matching predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        descendants(matching: .any)
            .matching(predicate)
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    public func tapButton(_ label: String) throws {
        let button = buttons[label]
        guard button.exists else {
            throw EvidenceError.navigationFailed("Button '\(label)' was not found.")
        }
        button.tap()
    }

    public func captureScreenshot() throws -> EvidenceScreenshot {
        EvidenceScreenshot(pngData: screenshot().pngRepresentation)
    }
}
