import CryptoKit
import Foundation

public protocol HTTPClient {
    func send(_ request: HTTPRequest) throws -> HTTPResponse
}

public struct HTTPRequest: Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data = Data()) {
        self.statusCode = statusCode
        self.body = body
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: HTTPRequest) throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<HTTPResponse, Error>!
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = .success(HTTPResponse(statusCode: statusCode, body: data ?? Data()))
        }.resume()
        semaphore.wait()
        return try result.get()
    }
}

public struct AppStoreScreenshotUploader {
    public var fileManager: FileManager
    public var httpClient: HTTPClient
    public var stdout: (String) -> Void
    public var now: () -> Date

    public init(
        fileManager: FileManager = .default,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        stdout: @escaping (String) -> Void = { print($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.httpClient = httpClient
        self.stdout = stdout
        self.now = now
    }

    public func upload(arguments: [String], config: EvidenceConfig, currentDirectory: URL) throws {
        guard let appStoreConfig = config.appStoreConnect else {
            throw CLIError.config("Missing [app_store_connect] configuration in .evidence.toml.")
        }

        let dryRun = arguments.contains("--dry-run")
        let localeFilter = optionValue("locale", in: arguments)
        let evidenceURL = url(forPath: config.evidenceDirectory, currentDirectory: currentDirectory)
        guard fileManager.fileExists(atPath: evidenceURL.path) else {
            throw CLIError.usage("Screenshot directory '\(evidenceURL.path)' does not exist. Run `evidence capture-screenshots` first.")
        }

        let screenshots = try ScreenshotUploadPlanner(
            fileManager: fileManager,
            evidenceDirectory: evidenceURL,
            localeFilter: localeFilter
        ).plan()
        guard !screenshots.isEmpty else {
            let suffix = localeFilter.map { " for locale '\($0)'" } ?? ""
            throw CLIError.usage("No uploadable PNG screenshots found in \(evidenceURL.path)\(suffix).")
        }

        let token = try AppStoreConnectJWT(config: appStoreConfig, currentDirectory: currentDirectory, now: now).token()
        let client = AppStoreConnectClient(
            httpClient: httpClient,
            token: token,
            appID: appStoreConfig.appID
        )

        let state = try client.fetchState(locales: Set(screenshots.map(\.locale)))
        let plans = screenshots.map { screenshot in
            UploadPlan(screenshot: screenshot, remote: state.remoteScreenshot(for: screenshot))
        }

        stdout(UploadPlanRenderer.render(plans))
        if dryRun {
            stdout("Dry run: no App Store Connect changes made.")
            return
        }

        for plan in plans where plan.action != .skip {
            guard let localization = state.localizationID(for: plan.screenshot.locale) else {
                throw CLIError.commandFailed("App Store Connect has no editable localization for '\(plan.screenshot.locale)'.")
            }
            let screenshotSetID = try state.screenshotSetID(
                locale: plan.screenshot.locale,
                displayType: plan.screenshot.displayType
            ) ?? client.createScreenshotSet(localizationID: localization, displayType: plan.screenshot.displayType)

            if let remoteID = plan.remoteID {
                try client.deleteScreenshot(id: remoteID)
            }
            try client.upload(plan.screenshot, screenshotSetID: screenshotSetID)
            stdout("Uploaded \(plan.screenshot.locale)/\(plan.screenshot.displayType)/\(plan.screenshot.fileName)")
        }
    }

    private func optionValue(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--\(name)") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private func url(forPath path: String, currentDirectory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return currentDirectory.appendingPathComponent(path)
    }
}

public struct LocalScreenshot: Equatable {
    public var url: URL
    public var locale: String
    public var deviceDirectory: String
    public var displayType: String
    public var slot: Int
    public var width: Int
    public var height: Int
    public var sourceFileChecksum: String
    public var fileSize: Int

    public var fileName: String {
        url.lastPathComponent
    }
}

public struct ScreenshotUploadPlanner {
    public var fileManager: FileManager
    public var evidenceDirectory: URL
    public var localeFilter: String?

    public init(fileManager: FileManager = .default, evidenceDirectory: URL, localeFilter: String? = nil) {
        self.fileManager = fileManager
        self.evidenceDirectory = evidenceDirectory
        self.localeFilter = localeFilter
    }

    public func plan() throws -> [LocalScreenshot] {
        guard let enumerator = fileManager.enumerator(at: evidenceDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }

        var screenshots: [LocalScreenshot] = []
        let evidencePrefix = evidenceDirectory.resolvingSymlinksInPath().path + "/"
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "png" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let resolved = url.resolvingSymlinksInPath().path
            let relative = resolved.hasPrefix(evidencePrefix)
                ? String(resolved.dropFirst(evidencePrefix.count))
                : String(url.path.dropFirst(evidenceDirectory.path.count + 1))
            let components = relative.split(separator: "/").map(String.init)
            guard components.count >= 2 else { continue }

            let parsed = parseLayout(components)
            guard localeFilter == nil || parsed.locale == localeFilter else { continue }
            guard let target = ScreenshotTarget(named: parsed.deviceDirectory),
                  let displayType = AppStoreScreenshotDisplayType.targetMap[target.name] else {
                continue
            }

            let data = try Data(contentsOf: url)
            let dimensions = try PNGDimensions.read(from: data, path: url.path)
            guard dimensions.width == target.width, dimensions.height == target.height else {
                throw CLIError.usage(
                    "Screenshot '\(relative)' is \(dimensions.width)x\(dimensions.height), " +
                    "but target '\(target.name)' requires \(target.width)x\(target.height)."
                )
            }
            screenshots.append(LocalScreenshot(
                url: url,
                locale: parsed.locale,
                deviceDirectory: parsed.deviceDirectory,
                displayType: displayType,
                slot: parsed.slot,
                width: dimensions.width,
                height: dimensions.height,
                sourceFileChecksum: Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                fileSize: data.count
            ))
        }

        return screenshots.sorted {
            if $0.locale != $1.locale { return $0.locale < $1.locale }
            if $0.displayType != $1.displayType { return $0.displayType < $1.displayType }
            if $0.slot != $1.slot { return $0.slot < $1.slot }
            return $0.fileName < $1.fileName
        }
    }

    private func parseLayout(_ components: [String]) -> (locale: String, deviceDirectory: String, slot: Int) {
        if components.count >= 3 {
            return (components[0], components[1], slot(from: components[2]))
        }
        return ("en-US", components[0], slot(from: components[1]))
    }

    private func slot(from fileName: String) -> Int {
        Self.slot(fromPublicFileName: fileName)
    }

    public static func slot(fromPublicFileName fileName: String) -> Int {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let prefix = stem.prefix { $0.isNumber }
        return Int(prefix) ?? 1
    }
}

public enum AppStoreScreenshotDisplayType {
    public static let targetMap: [String: String] = [
        "6.9": "APP_IPHONE_67",
        "6.5": "APP_IPHONE_65",
        "6.1": "APP_IPHONE_61",
        "5.5": "APP_IPHONE_55",
        "ipad-13": "APP_IPAD_PRO_3GEN_129",
        "ipad-12.9": "APP_IPAD_PRO_3GEN_129",
        "ipad-11": "APP_IPAD_PRO_3GEN_11"
    ]
}

public struct PNGDimensions: Equatable {
    public var width: Int
    public var height: Int

    public static func read(from data: Data, path: String) throws -> PNGDimensions {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, Array(data.prefix(8)) == signature else {
            throw CLIError.usage("Screenshot '\(path)' is not a valid PNG file.")
        }
        func uint32(at offset: Int) -> Int {
            data[offset..<offset + 4].reduce(0) { ($0 << 8) + Int($1) }
        }
        return PNGDimensions(width: uint32(at: 16), height: uint32(at: 20))
    }
}

public struct RemoteScreenshot: Equatable {
    public var id: String
    public var locale: String
    public var displayType: String
    public var slot: Int
    public var checksum: String?
}

public enum UploadAction: Equatable {
    case create
    case replace
    case skip
}

public struct UploadPlan: Equatable {
    public var screenshot: LocalScreenshot
    public var action: UploadAction
    public var remoteID: String?

    public init(screenshot: LocalScreenshot, remote: RemoteScreenshot?) {
        self.screenshot = screenshot
        self.remoteID = remote?.id
        if let remote, remote.checksum == screenshot.sourceFileChecksum {
            self.action = .skip
        } else if remote != nil {
            self.action = .replace
        } else {
            self.action = .create
        }
    }
}

public enum UploadPlanRenderer {
    public static func render(_ plans: [UploadPlan]) -> String {
        var lines = [
            "| Locale | Display | Slot | File | Size | Hash match | Action |",
            "| --- | --- | ---: | --- | ---: | :---: | --- |"
        ]
        for plan in plans {
            let match = plan.action == .skip ? "✓" : "✗"
            let action: String
            switch plan.action {
            case .create:
                action = "create"
            case .replace:
                action = "replace"
            case .skip:
                action = "skip"
            }
            lines.append(
                "| \(plan.screenshot.locale) | \(plan.screenshot.displayType) | \(plan.screenshot.slot) | " +
                "`\(plan.screenshot.fileName)` | \(plan.screenshot.fileSize) | \(match) | \(action) |"
            )
        }
        return lines.joined(separator: "\n")
    }
}

public struct AppStoreConnectState {
    public var localizations: [String: String]
    public var screenshotSets: [String: String]
    public var screenshots: [RemoteScreenshot]

    public init(localizations: [String: String] = [:], screenshotSets: [String: String] = [:], screenshots: [RemoteScreenshot] = []) {
        self.localizations = localizations
        self.screenshotSets = screenshotSets
        self.screenshots = screenshots
    }

    public func localizationID(for locale: String) -> String? {
        localizations[locale]
    }

    public func screenshotSetID(locale: String, displayType: String) -> String? {
        screenshotSets["\(locale)|\(displayType)"]
    }

    public func remoteScreenshot(for screenshot: LocalScreenshot) -> RemoteScreenshot? {
        screenshots.first {
            $0.locale == screenshot.locale &&
            $0.displayType == screenshot.displayType &&
            $0.slot == screenshot.slot
        }
    }
}

public struct AppStoreConnectClient {
    public var httpClient: HTTPClient
    public var token: String
    public var appID: String
    public var baseURL: URL

    public init(httpClient: HTTPClient, token: String, appID: String, baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com/v1")!) {
        self.httpClient = httpClient
        self.token = token
        self.appID = appID
        self.baseURL = baseURL
    }

    public func fetchState(locales: Set<String>) throws -> AppStoreConnectState {
        let versions = try getJSON("/apps/\(appID)/appStoreVersions?filter[platform]=IOS&include=appStoreVersionLocalizations&limit=1")
        let included = versions["included"] as? [[String: Any]] ?? []
        var localizations: [String: String] = [:]
        for item in included where item["type"] as? String == "appStoreVersionLocalizations" {
            guard let id = item["id"] as? String,
                  let attributes = item["attributes"] as? [String: Any],
                  let locale = attributes["locale"] as? String,
                  locales.contains(locale) else {
                continue
            }
            localizations[locale] = id
        }

        var state = AppStoreConnectState(localizations: localizations)
        for (locale, localizationID) in localizations {
            let sets = try getJSON("/appScreenshotSets?filter[appStoreVersionLocalization]=\(localizationID)&include=appScreenshots&limit=200")
            let data = sets["data"] as? [[String: Any]] ?? []
            for item in data where item["type"] as? String == "appScreenshotSets" {
                guard let id = item["id"] as? String,
                      let attributes = item["attributes"] as? [String: Any],
                      let displayType = attributes["screenshotDisplayType"] as? String else {
                    continue
                }
                state.screenshotSets["\(locale)|\(displayType)"] = id
            }

            let includedScreenshots = sets["included"] as? [[String: Any]] ?? []
            for item in includedScreenshots where item["type"] as? String == "appScreenshots" {
                guard let id = item["id"] as? String,
                      let attributes = item["attributes"] as? [String: Any] else {
                    continue
                }
                let fileName = attributes["fileName"] as? String ?? ""
                let displayType = attributes["screenshotDisplayType"] as? String
                    ?? displayTypeForScreenshot(item: item, sets: data)
                    ?? ""
                let slot = attributes["sortOrder"] as? Int ?? ScreenshotUploadPlanner.slot(fromPublicFileName: fileName)
                let checksum = attributes["sourceFileChecksum"] as? String
                state.screenshots.append(RemoteScreenshot(
                    id: id,
                    locale: locale,
                    displayType: displayType,
                    slot: slot,
                    checksum: checksum
                ))
            }
        }
        return state
    }

    public func createScreenshotSet(localizationID: String, displayType: String) throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshotSets",
                "attributes": ["screenshotDisplayType": displayType],
                "relationships": [
                    "appStoreVersionLocalization": [
                        "data": ["type": "appStoreVersionLocalizations", "id": localizationID]
                    ]
                ]
            ]
        ]
        let response = try sendJSON("POST", path: "/appScreenshotSets", body: body)
        guard let data = response["data"] as? [String: Any], let id = data["id"] as? String else {
            throw CLIError.commandFailed("App Store Connect did not return an app screenshot set id.")
        }
        return id
    }

    public func deleteScreenshot(id: String) throws {
        _ = try request("DELETE", path: "/appScreenshots/\(id)")
    }

    public func upload(_ screenshot: LocalScreenshot, screenshotSetID: String) throws {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshots",
                "attributes": [
                    "fileName": screenshot.fileName,
                    "fileSize": screenshot.fileSize
                ],
                "relationships": [
                    "appScreenshotSet": [
                        "data": ["type": "appScreenshotSets", "id": screenshotSetID]
                    ]
                ]
            ]
        ]
        let created = try sendJSON("POST", path: "/appScreenshots", body: body)
        guard let data = created["data"] as? [String: Any],
              let screenshotID = data["id"] as? String,
              let attributes = data["attributes"] as? [String: Any],
              let operations = attributes["uploadOperations"] as? [[String: Any]] else {
            throw CLIError.commandFailed("App Store Connect did not return upload operations for \(screenshot.fileName).")
        }

        let bytes = try Data(contentsOf: screenshot.url)
        for operation in operations {
            try uploadChunk(operation: operation, bytes: bytes)
        }

        _ = try sendJSON("PATCH", path: "/appScreenshots/\(screenshotID)", body: [
            "data": [
                "type": "appScreenshots",
                "id": screenshotID,
                "attributes": [
                    "uploaded": true,
                    "sourceFileChecksum": screenshot.sourceFileChecksum
                ]
            ]
        ])
    }

    private func uploadChunk(operation: [String: Any], bytes: Data) throws {
        guard let method = operation["method"] as? String,
              let urlString = operation["url"] as? String,
              let url = URL(string: urlString) else {
            throw CLIError.commandFailed("Malformed App Store Connect upload operation.")
        }
        let offset = operation["offset"] as? Int ?? 0
        let length = operation["length"] as? Int ?? bytes.count
        let end = min(offset + length, bytes.count)
        guard offset <= end else {
            throw CLIError.commandFailed("Malformed App Store Connect upload byte range.")
        }
        var headers = requestHeaders(from: operation["requestHeaders"])
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "image/png"
        }
        let response = try httpClient.send(HTTPRequest(
            method: method,
            url: url,
            headers: headers,
            body: bytes.subdata(in: offset..<end)
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw CLIError.commandFailed("App Store Connect upload failed with HTTP \(response.statusCode).")
        }
    }

    private func requestHeaders(from raw: Any?) -> [String: String] {
        if let dictionary = raw as? [String: String] {
            return dictionary
        }
        guard let pairs = raw as? [[String: Any]] else {
            return [:]
        }
        var headers: [String: String] = [:]
        for pair in pairs {
            guard let name = pair["name"] as? String,
                  let value = pair["value"] as? String else {
                continue
            }
            headers[name] = value
        }
        return headers
    }

    private func getJSON(_ path: String) throws -> [String: Any] {
        try sendJSON("GET", path: path, body: nil)
    }

    private func sendJSON(_ method: String, path: String, body: [String: Any]?) throws -> [String: Any] {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        let response = try request(method, path: path, body: data)
        guard !response.body.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw CLIError.commandFailed("App Store Connect returned non-JSON response.")
        }
        return json
    }

    private func request(_ method: String, path: String, body: Data? = nil) throws -> HTTPResponse {
        let url = path.hasPrefix("http")
            ? URL(string: path)!
            : URL(string: baseURL.absoluteString + (path.hasPrefix("/") ? path : "/" + path))!
        var headers = ["Authorization": "Bearer \(token)"]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        let response = try httpClient.send(HTTPRequest(method: method, url: url, headers: headers, body: body))
        guard (200..<300).contains(response.statusCode) else {
            let excerpt = String(data: response.body, encoding: .utf8) ?? ""
            throw CLIError.commandFailed("App Store Connect request \(method) \(path) failed with HTTP \(response.statusCode). \(excerpt)")
        }
        return response
    }

    private func displayTypeForScreenshot(item: [String: Any], sets: [[String: Any]]) -> String? {
        guard let relationships = item["relationships"] as? [String: Any],
              let set = relationships["appScreenshotSet"] as? [String: Any],
              let data = set["data"] as? [String: Any],
              let setID = data["id"] as? String else {
            return nil
        }
        return sets.first { $0["id"] as? String == setID }
            .flatMap { $0["attributes"] as? [String: Any] }?["screenshotDisplayType"] as? String
    }
}

public struct AppStoreConnectJWT {
    public var config: AppStoreConnectConfig
    public var currentDirectory: URL
    public var now: () -> Date

    public init(
        config: AppStoreConnectConfig,
        currentDirectory: URL,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.currentDirectory = currentDirectory
        self.now = now
    }

    public func token() throws -> String {
        let keyURL = config.p8Path.hasPrefix("/")
            ? URL(fileURLWithPath: config.p8Path)
            : currentDirectory.appendingPathComponent(config.p8Path)
        let pem = try String(contentsOf: keyURL, encoding: .utf8)
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        let issuedAt = Int(now().timeIntervalSince1970)
        let expiresAt = issuedAt + 20 * 60
        let header = try jsonBase64URL([
            "alg": "ES256",
            "kid": config.keyID,
            "typ": "JWT"
        ])
        let payload = try jsonBase64URL([
            "aud": "appstoreconnect-v1",
            "iss": config.issuerID,
            "iat": issuedAt,
            "exp": expiresAt
        ] as [String: Any])
        let signingInput = "\(header).\(payload)"
        let signature = try privateKey.signature(for: Data(signingInput.utf8)).rawRepresentation.base64URLEncodedString()
        return "\(signingInput).\(signature)"
    }

    private func jsonBase64URL(_ object: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
