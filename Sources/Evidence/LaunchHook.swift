import Foundation

/// Launch-time customization for a consuming app's UI test target.
public struct LaunchHook: Equatable {
    public var launchArguments: [String]
    public var launchEnvironment: [String: String]

    public init(
        launchArguments: [String] = [],
        launchEnvironment: [String: String] = [:]
    ) {
        self.launchArguments = launchArguments
        self.launchEnvironment = launchEnvironment
    }

    public static let none = LaunchHook()
}
