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
    func tapElement(_ label: String) throws
    func typeText(_ text: String, intoElement label: String) throws
    func openURL(_ url: URL) throws
    func swipeLeft()
    func swipe(_ direction: NavigationAction.SwipeDirection) throws
    func captureScreenshot() throws -> EvidenceScreenshot
}

public extension EvidenceApplication {
    mutating func apply(_ launchHook: LaunchHook) {
        launchArguments.append(contentsOf: launchHook.launchArguments)
        launchEnvironment.merge(launchHook.launchEnvironment) { _, new in new }
    }

    func tapElement(_ label: String) throws {
        try tapButton(label)
    }

    func typeText(_ text: String, intoElement label: String) throws {
        throw EvidenceError.navigationFailed("Typing text into '\(label)' is not supported by this application adapter.")
    }

    func openURL(_ url: URL) throws {
        throw EvidenceError.navigationFailed("Opening URL '\(url.absoluteString)' is not supported by this application adapter.")
    }

    func swipe(_ direction: NavigationAction.SwipeDirection) throws {
        switch direction {
        case .left:
            swipeLeft()
        case .up, .down, .right:
            throw EvidenceError.navigationFailed("Swipe direction '\(direction.rawValue)' is not supported by this application adapter.")
        }
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

    public func tapElement(_ label: String) throws {
        let element = descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        guard element.exists else {
            throw EvidenceError.navigationFailed("Element '\(label)' was not found.")
        }
        element.tap()
    }

    public func typeText(_ text: String, intoElement label: String) throws {
        let element = descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        guard element.exists else {
            throw EvidenceError.navigationFailed("Text input '\(label)' was not found.")
        }
        element.tap()
        element.typeText(text)
    }

    public func openURL(_ url: URL) throws {
        open(url)
    }

    public func swipe(_ direction: NavigationAction.SwipeDirection) throws {
        switch direction {
        case .up:
            swipeUp()
        case .down:
            swipeDown()
        case .left:
            swipeLeft()
        case .right:
            swipeRight()
        }
    }

    public func captureScreenshot() throws -> EvidenceScreenshot {
        EvidenceScreenshot(pngData: screenshot().pngRepresentation)
    }
}
