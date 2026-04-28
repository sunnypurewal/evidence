import Foundation

public struct TOMLDocument: Equatable {
    private var values: [String: TOMLValue]

    public init(values: [String: TOMLValue]) {
        self.values = values
    }

    public init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        self = try TOMLDocument.parse(text)
    }

    public static func parse(_ text: String) throws -> TOMLDocument {
        var values: [String: TOMLValue] = [:]

        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, !parts[0].isEmpty else {
                throw CLIError.config("Invalid .evidence.toml line \(lineNumber): expected key = value.")
            }

            values[parts[0]] = try parseValue(parts[1], field: parts[0], line: lineNumber)
        }

        return TOMLDocument(values: values)
    }

    public func string(_ key: String) -> String? {
        guard case let .string(value) = values[key] else {
            return nil
        }
        return value
    }

    public func stringArray(_ key: String) -> [String]? {
        guard case let .stringArray(value) = values[key] else {
            return nil
        }
        return value
    }

    public func int(_ key: String) -> Int? {
        guard case let .int(value) = values[key] else {
            return nil
        }
        return value
    }

    public func double(_ key: String) -> Double? {
        switch values[key] {
        case let .double(value):
            return value
        case let .int(value):
            return Double(value)
        default:
            return nil
        }
    }

    public func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.isEmpty else {
            throw CLIError.config("Missing required field '\(key)' in .evidence.toml.")
        }
        return value
    }

    private static func parseValue(_ text: String, field: String, line: Int) throws -> TOMLValue {
        if text.hasPrefix("\""), text.hasSuffix("\"") {
            return .string(String(text.dropFirst().dropLast()))
        }

        if text.hasPrefix("["), text.hasSuffix("]") {
            let body = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                return .stringArray([])
            }

            let values = body.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard values.allSatisfy({ $0.hasPrefix("\"") && $0.hasSuffix("\"") }) else {
                throw CLIError.config("Invalid field '\(field)' on line \(line): arrays must contain quoted strings.")
            }
            return .stringArray(values.map { String($0.dropFirst().dropLast()) })
        }

        if let int = Int(text) {
            return .int(int)
        }

        if let double = Double(text) {
            return .double(double)
        }

        throw CLIError.config("Invalid field '\(field)' on line \(line): unsupported TOML value.")
    }

    private static func stripComment(_ line: String) -> String {
        var inString = false
        var result = ""
        for character in line {
            if character == "\"" {
                inString.toggle()
            }
            if character == "#", !inString {
                break
            }
            result.append(character)
        }
        return result
    }
}

public enum TOMLValue: Equatable {
    case string(String)
    case stringArray([String])
    case int(Int)
    case double(Double)
}
