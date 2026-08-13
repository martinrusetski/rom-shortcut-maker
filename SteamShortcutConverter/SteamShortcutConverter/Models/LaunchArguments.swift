//
//  LaunchArguments.swift
//  SteamShortcutConverter
//
//  Structured launch-argument parsing, validation, and placeholder expansion.
//  Executables are deliberately not part of this model.
//

import Foundation

enum LaunchArgumentError: LocalizedError, Equatable {
    case unmatchedQuote
    case unknownPlaceholder(String)
    case missingCore

    var errorDescription: String? {
        switch self {
        case .unmatchedQuote:
            return "The custom arguments contain an unmatched quote."
        case .unknownPlaceholder(let placeholder):
            return "Unknown launch placeholder: \(placeholder)."
        case .missingCore:
            return "The arguments require a RetroArch core, but no core is selected."
        }
    }
}

enum LaunchArguments {
    static let supportedPlaceholders = [
        "{romPath}",
        "{romDirectory}",
        "{romFilename}",
        "{romStem}",
        "{corePath}"
    ]

    private static let supportedPlaceholderSet = Set(supportedPlaceholders)

    /// Parse an arguments-only command line into tokens. Quotes group whitespace
    /// and are removed because generated launchers quote every resolved token.
    static func parse(_ text: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasContent = false
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for character in text {
            if isEscaping {
                current.append(character)
                hasContent = true
                isEscaping = false
            } else if character == "\\" && !inSingleQuote {
                isEscaping = true
                hasContent = true
            } else if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                hasContent = true
            } else if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                hasContent = true
            } else if character.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if hasContent { tokens.append(current) }
                current = ""
                hasContent = false
            } else {
                current.append(character)
                hasContent = true
            }
        }

        guard !inSingleQuote && !inDoubleQuote else {
            throw LaunchArgumentError.unmatchedQuote
        }
        if isEscaping { current.append("\\") }
        if hasContent { tokens.append(current) }
        try validate(tokens)
        return tokens
    }

    /// A stable, editable representation for the Advanced text field.
    static func format(_ arguments: [String]) -> String {
        arguments.map(formatToken).joined(separator: " ")
    }

    static func validate(_ arguments: [String]) throws {
        for argument in arguments {
            for placeholder in placeholders(in: argument) {
                guard supportedPlaceholderSet.contains(placeholder) else {
                    throw LaunchArgumentError.unknownPlaceholder(placeholder)
                }
            }
            let literalRemainder = supportedPlaceholders.reduce(argument) {
                $0.replacingOccurrences(of: $1, with: "")
            }
            if literalRemainder.contains("{") || literalRemainder.contains("}") {
                throw LaunchArgumentError.unknownPlaceholder(argument)
            }
        }
    }

    static func resolve(_ arguments: [String], rom: URL, core: URL?) throws -> [String] {
        try validate(arguments)
        if arguments.contains(where: { $0.contains("{corePath}") }) && core == nil {
            throw LaunchArgumentError.missingCore
        }
        let values = [
            "{romPath}": rom.path,
            "{romDirectory}": rom.deletingLastPathComponent().path,
            "{romFilename}": rom.lastPathComponent,
            "{romStem}": rom.deletingPathExtension().lastPathComponent,
            "{corePath}": core?.path ?? ""
        ]
        return arguments.map { argument in
            values.reduce(argument) { value, replacement in
                value.replacingOccurrences(of: replacement.key, with: replacement.value)
            }
        }
    }

    private static func placeholders(in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\{[^{}]+\}"#) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    private static func formatToken(_ token: String) -> String {
        guard token.isEmpty || token.contains(where: {
            $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\"
        }) else {
            return token
        }
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
