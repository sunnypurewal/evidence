import Foundation

/// A visible condition that proves a scene is ready to capture.
public enum PlanAnchor: Equatable, CustomStringConvertible {
    case staticText(String)
    case button(String)
    case predicate(format: String)

    public var description: String {
        switch self {
        case let .staticText(label):
            "static text '\(label)'"
        case let .button(label):
            "button '\(label)'"
        case let .predicate(format):
            "predicate '\(format)'"
        }
    }

    func wait(in app: EvidenceApplication, timeout: TimeInterval) -> Bool {
        switch self {
        case let .staticText(label):
            app.waitForStaticText(label, timeout: timeout)
        case let .button(label):
            app.waitForButton(label, timeout: timeout)
        case let .predicate(format):
            app.waitForElement(matching: NSPredicate(format: format), timeout: timeout)
        }
    }
}
