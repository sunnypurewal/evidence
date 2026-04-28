import Foundation

public struct MarketingRenderer {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var toolPaths: ToolPaths

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunning,
        toolPaths: ToolPaths = ToolPaths()
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.toolPaths = toolPaths
    }

    public func loadScene(from url: URL, target: ScreenshotTarget) throws -> MarketingScene {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try MarketingScene.parse(json, target: target)
    }

    @discardableResult
    public func render(scene: MarketingScene, svgURL: URL, pngURL: URL?) throws -> String {
        let svg = MarketingSVGRenderer(scene: scene).render()
        try fileManager.createDirectory(at: svgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try svg.write(to: svgURL, atomically: true, encoding: .utf8)

        if let pngURL {
            try fileManager.createDirectory(at: pngURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let result = try runner.run(toolPaths.magick, [svgURL.path, pngURL.path])
            guard result.exitCode == 0 else {
                throw CLIError.commandFailed("Marketing PNG render failed. \(result.stderr)")
            }
        }

        return svg
    }
}

public struct MarketingScene: Equatable {
    public var id: String
    public var width: Int
    public var height: Int
    public var background: String
    public var deviceFrame: DeviceFrame?
    public var headline: String
    public var subhead: String?
    public var sourceText: String?
    public var rows: [MarketingRow]

    public static func parse(_ json: Any, target: ScreenshotTarget) throws -> MarketingScene {
        let root = try JSONObject(json, context: "root")
        let scenes = try root.objectArray("scenes", context: "root")
        guard let first = scenes.first else {
            throw CLIError.config("Invalid key 'scenes': expected at least one scene.")
        }
        return try parseScene(first, index: 0, target: target)
    }

    private static func parseScene(_ object: [String: Any], index: Int, target: ScreenshotTarget) throws -> MarketingScene {
        let scene = JSONObject(object, context: "scene \(index)")
        try scene.validateKeys([
            "id",
            "width",
            "height",
            "background",
            "device_frame",
            "headline",
            "subhead",
            "source_text",
            "rows"
        ])
        let id = try scene.requiredString("id")
        let rows = try scene.objectArray("rows", context: "scene '\(id)'", required: false)
            .enumerated()
            .map { try MarketingRow.parse($0.element, sceneID: id, index: $0.offset) }

        return MarketingScene(
            id: id,
            width: try scene.int("width", required: false) ?? target.width,
            height: try scene.int("height", required: false) ?? target.height,
            background: try scene.string("background", required: false) ?? "#f8fafc",
            deviceFrame: try DeviceFrame.parse(scene.object("device_frame", required: false), sceneID: id),
            headline: try scene.requiredString("headline"),
            subhead: try scene.string("subhead", required: false),
            sourceText: try scene.string("source_text", required: false),
            rows: rows
        )
    }
}

public struct DeviceFrame: Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var cornerRadius: Int
    public var fill: String

    static func parse(_ object: [String: Any]?, sceneID: String) throws -> DeviceFrame? {
        guard let object else {
            return nil
        }
        let frame = JSONObject(object, context: "scene '\(sceneID)' device_frame")
        try frame.validateKeys([
            "x",
            "y",
            "width",
            "height",
            "corner_radius",
            "fill"
        ])
        return DeviceFrame(
            x: try frame.requiredInt("x"),
            y: try frame.requiredInt("y"),
            width: try frame.requiredInt("width"),
            height: try frame.requiredInt("height"),
            cornerRadius: try frame.int("corner_radius", required: false) ?? 64,
            fill: try frame.string("fill", required: false) ?? "#111827"
        )
    }
}

public indirect enum MarketingRow: Equatable {
    case left(title: String, text: String)
    case right(title: String, text: String)
    case badge(text: String)
    case metric(label: String, value: String)
    case timeline(title: String, items: [String])
    case stage(label: String, status: String)
    case row(title: String, detail: String)
    case compose(rows: [MarketingRow])

    static func parse(_ object: [String: Any], sceneID: String, index: Int) throws -> MarketingRow {
        let row = JSONObject(object, context: "scene '\(sceneID)' row \(index)")
        let kind = try row.requiredString("kind")

        switch kind {
        case "left":
            try row.validateKeys(["kind", "title", "text"])
            return .left(title: try row.requiredString("title"), text: try row.requiredString("text"))
        case "right":
            try row.validateKeys(["kind", "title", "text"])
            return .right(title: try row.requiredString("title"), text: try row.requiredString("text"))
        case "badge":
            try row.validateKeys(["kind", "text"])
            return .badge(text: try row.requiredString("text"))
        case "metric":
            try row.validateKeys(["kind", "label", "value"])
            return .metric(label: try row.requiredString("label"), value: try row.requiredString("value"))
        case "timeline":
            try row.validateKeys(["kind", "title", "items"])
            return .timeline(title: try row.requiredString("title"), items: try row.stringArray("items"))
        case "stage":
            try row.validateKeys(["kind", "label", "status"])
            return .stage(label: try row.requiredString("label"), status: try row.requiredString("status"))
        case "row":
            try row.validateKeys(["kind", "title", "detail"])
            return .row(title: try row.requiredString("title"), detail: try row.requiredString("detail"))
        case "compose":
            try row.validateKeys(["kind", "rows"])
            let children = try row.objectArray("rows", context: "scene '\(sceneID)' row \(index)")
            return .compose(rows: try children.enumerated().map {
                try MarketingRow.parse($0.element, sceneID: sceneID, index: index * 100 + $0.offset)
            })
        default:
            throw CLIError.config("Invalid scene '\(sceneID)' row \(index) key 'kind': unknown row kind '\(kind)'.")
        }
    }
}

private struct MarketingSVGRenderer {
    var scene: MarketingScene

    func render() -> String {
        var svg: [String] = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(scene.width)\" height=\"\(scene.height)\" viewBox=\"0 0 \(scene.width) \(scene.height)\">",
            "<rect width=\"100%\" height=\"100%\" fill=\"\(escape(scene.background))\"/>"
        ]

        if let frame = scene.deviceFrame {
            svg.append("<rect x=\"\(frame.x)\" y=\"\(frame.y)\" width=\"\(frame.width)\" height=\"\(frame.height)\" rx=\"\(frame.cornerRadius)\" fill=\"\(escape(frame.fill))\"/>")
            svg.append("<rect x=\"\(frame.x + 32)\" y=\"\(frame.y + 32)\" width=\"\(max(0, frame.width - 64))\" height=\"\(max(0, frame.height - 64))\" rx=\"\(max(0, frame.cornerRadius - 20))\" fill=\"#ffffff\"/>")
        }

        let margin = max(72, scene.width / 14)
        var y = margin
        svg.append(text(scene.headline, x: margin, y: y, size: 84, weight: "700", fill: "#111827"))
        y += 96

        if let subhead = scene.subhead {
            svg.append(text(subhead, x: margin, y: y, size: 42, weight: "500", fill: "#334155"))
            y += 70
        }

        for row in scene.rows {
            svg.append(contentsOf: render(row: row, x: margin, y: y, width: scene.width - margin * 2))
            y += rowHeight(row) + 24
        }

        if let sourceText = scene.sourceText {
            svg.append(text(sourceText, x: margin, y: scene.height - margin, size: 28, weight: "400", fill: "#64748b"))
        }

        svg.append("</svg>")
        return svg.joined(separator: "\n")
    }

    private func render(row: MarketingRow, x: Int, y: Int, width: Int) -> [String] {
        switch row {
        case let .left(title, textValue):
            return card(x: x, y: y, width: width, height: 132, accent: "#2563eb")
                + [text(title, x: x + 36, y: y + 52, size: 34, weight: "700", fill: "#111827"),
                   text(textValue, x: x + 36, y: y + 98, size: 30, weight: "400", fill: "#475569")]
        case let .right(title, textValue):
            return card(x: x, y: y, width: width, height: 132, accent: "#0f766e")
                + [text(title, x: x + width / 2, y: y + 52, size: 34, weight: "700", fill: "#111827"),
                   text(textValue, x: x + width / 2, y: y + 98, size: 30, weight: "400", fill: "#475569")]
        case let .badge(textValue):
            return ["<rect x=\"\(x)\" y=\"\(y)\" width=\"\(min(width, 520))\" height=\"78\" rx=\"39\" fill=\"#dcfce7\"/>",
                    text(textValue, x: x + 36, y: y + 51, size: 32, weight: "700", fill: "#166534")]
        case let .metric(label, value):
            return card(x: x, y: y, width: width, height: 148, accent: "#7c3aed")
                + [text(value, x: x + 36, y: y + 66, size: 54, weight: "800", fill: "#111827"),
                   text(label, x: x + 36, y: y + 114, size: 28, weight: "500", fill: "#64748b")]
        case let .timeline(title, items):
            var output = card(x: x, y: y, width: width, height: rowHeight(row), accent: "#ea580c")
            output.append(text(title, x: x + 36, y: y + 52, size: 34, weight: "700", fill: "#111827"))
            for (index, item) in items.enumerated() {
                let itemY = y + 100 + index * 44
                output.append("<circle cx=\"\(x + 48)\" cy=\"\(itemY - 8)\" r=\"7\" fill=\"#ea580c\"/>")
                output.append(text(item, x: x + 72, y: itemY, size: 28, weight: "400", fill: "#475569"))
            }
            return output
        case let .stage(label, status):
            return card(x: x, y: y, width: width, height: 112, accent: "#0891b2")
                + [text(label, x: x + 36, y: y + 48, size: 30, weight: "700", fill: "#111827"),
                   text(status, x: x + width - 260, y: y + 48, size: 30, weight: "700", fill: "#0891b2")]
        case let .row(title, detail):
            return card(x: x, y: y, width: width, height: 118, accent: "#475569")
                + [text(title, x: x + 36, y: y + 48, size: 30, weight: "700", fill: "#111827"),
                   text(detail, x: x + 36, y: y + 90, size: 26, weight: "400", fill: "#64748b")]
        case let .compose(rows):
            var output: [String] = []
            var childY = y
            for child in rows {
                output.append(contentsOf: render(row: child, x: x, y: childY, width: width))
                childY += rowHeight(child) + 16
            }
            return output
        }
    }

    private func card(x: Int, y: Int, width: Int, height: Int, accent: String) -> [String] {
        [
            "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"28\" fill=\"#ffffff\"/>",
            "<rect x=\"\(x)\" y=\"\(y)\" width=\"10\" height=\"\(height)\" rx=\"5\" fill=\"\(accent)\"/>"
        ]
    }

    private func rowHeight(_ row: MarketingRow) -> Int {
        switch row {
        case .left, .right:
            132
        case .badge:
            78
        case .metric:
            148
        case let .timeline(_, items):
            118 + items.count * 44
        case .stage:
            112
        case .row:
            118
        case let .compose(rows):
            rows.map(rowHeight).reduce(0, +) + max(0, rows.count - 1) * 16
        }
    }

    private func text(_ value: String, x: Int, y: Int, size: Int, weight: String, fill: String) -> String {
        "<text x=\"\(x)\" y=\"\(y)\" font-family=\"-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif\" font-size=\"\(size)\" font-weight=\"\(weight)\" fill=\"\(fill)\">\(escape(value))</text>"
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private struct JSONObject {
    var values: [String: Any]
    var context: String

    init(_ value: Any, context: String) throws {
        guard let values = value as? [String: Any] else {
            throw CLIError.config("Invalid \(context): expected object.")
        }
        self.values = values
        self.context = context
    }

    init(_ values: [String: Any], context: String) {
        self.values = values
        self.context = context
    }

    func string(_ key: String, required: Bool = true) throws -> String? {
        guard let value = values[key] else {
            if required {
                throw CLIError.config("Invalid \(context) key '\(key)': expected string.")
            }
            return nil
        }
        guard let string = value as? String, !string.isEmpty else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected non-empty string.")
        }
        return string
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = try string(key, required: true) else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected string.")
        }
        return value
    }

    func int(_ key: String, required: Bool = true) throws -> Int? {
        guard let value = values[key] else {
            if required {
                throw CLIError.config("Invalid \(context) key '\(key)': expected integer.")
            }
            return nil
        }
        guard let int = value as? Int else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected integer.")
        }
        return int
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let value = try int(key, required: true) else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected integer.")
        }
        return value
    }

    func stringArray(_ key: String) throws -> [String] {
        guard let values = values[key] as? [String], !values.isEmpty else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected array of strings.")
        }
        return values
    }

    func object(_ key: String, required: Bool = true) throws -> [String: Any]? {
        guard let value = values[key] else {
            if required {
                throw CLIError.config("Invalid \(context) key '\(key)': expected object.")
            }
            return nil
        }
        guard let object = value as? [String: Any] else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected object.")
        }
        return object
    }

    func objectArray(_ key: String, context: String, required: Bool = true) throws -> [[String: Any]] {
        guard let value = values[key] else {
            if required {
                throw CLIError.config("Invalid \(context) key '\(key)': expected array of objects.")
            }
            return []
        }
        guard let objects = value as? [[String: Any]] else {
            throw CLIError.config("Invalid \(context) key '\(key)': expected array of objects.")
        }
        return objects
    }

    func validateKeys(_ allowedKeys: Set<String>) throws {
        for key in values.keys.sorted() where !allowedKeys.contains(key) {
            throw CLIError.config("Invalid \(context) key '\(key)': unsupported key.")
        }
    }
}
