import Foundation

/// Navigation that moves the app from one scene to the next.
public enum NavigationAction {
    case swipeLeft
    case tap(label: String)
    case run((EvidenceApplication) throws -> Void)

    func perform(in app: EvidenceApplication) throws {
        switch self {
        case .swipeLeft:
            app.swipeLeft()
        case let .tap(label):
            try app.tapButton(label)
        case let .run(action):
            try action(app)
        }
    }
}
