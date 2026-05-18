import Foundation

/// Navigation that moves the app from one scene to the next.
public enum NavigationAction {
    case swipeLeft
    case swipe(direction: SwipeDirection)
    case tap(label: String)
    case tapElement(label: String)
    case typeText(label: String, text: String)
    case openURL(URL)
    case run((EvidenceApplication) throws -> Void)

    public enum SwipeDirection: String, Codable, Equatable {
        case up
        case down
        case left
        case right
    }

    func perform(in app: EvidenceApplication) throws {
        switch self {
        case .swipeLeft:
            app.swipeLeft()
        case let .swipe(direction):
            try app.swipe(direction)
        case let .tap(label):
            try app.tapButton(label)
        case let .tapElement(label):
            try app.tapElement(label)
        case let .typeText(label, text):
            try app.typeText(text, intoElement: label)
        case let .openURL(url):
            try app.openURL(url)
        case let .run(action):
            try action(app)
        }
    }
}
