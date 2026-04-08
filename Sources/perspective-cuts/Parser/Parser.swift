import Foundation

struct ParserError: Error, CustomStringConvertible {
    let message: String
    let location: SourceLocation

    var description: String { "Parse error at \(location): \(message)" }
}

struct Parser: Sendable {
    private let tokens: [Token]

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    func parse() throws -> [ASTNode] {
        var nodes: [ASTNode] = []
        var pos = 0

        while pos < tokens.count {
            skipNewlines(&pos)
            guard pos < tokens.count, tokens[pos].kind != .eof else { break }

            let node = try parseStatement(&pos)
            nodes.append(node)
        }
        return nodes
    }

    // MARK: - Statement Parsing

    private func parseStatement(_ pos: inout Int) throws -> ASTNode {
        let token = tokens[pos]
        switch token.kind {
        case .importKeyword:
            return try parseImport(&pos)
        case .hash:
            return try parseMetadata(&pos)
        case .comment(let text):
            pos += 1
            return .comment(text: text, location: token.location)
        case .letKeyword, .varKeyword:
            return try parseVariableDeclaration(&pos)
        case .ifKeyword:
            return try parseIf(&pos)
        case .repeatKeyword:
            return try parseRepeat(&pos)
        case .forKeyword:
            return try parseForEach(&pos)
        case .menuKeyword:
            return try parseMenu(&pos)
        case .funcKeyword:
            return try parseFunction(&pos)
        case .returnKeyword:
            return try parseReturn(&pos)
        case .identifier:
            return try parseActionCall(&pos)
        default:
            throw ParserError(message: "Unexpected token: \(token.kind)", location: token.location)
        }
    }

    // MARK: - Import

    private func parseImport(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip 'import'
        guard pos < tokens.count, case .identifier(let module) = tokens[pos].kind else {
            throw ParserError(message: "Expected module name after 'import'", location: loc)
        }
        pos += 1
        return .importStatement(module: module, location: loc)
    }

    // MARK: - Metadata (#color: blue, #icon: gear)

    private func parseMetadata(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip #
        guard pos < tokens.count, case .identifier(let key) = tokens[pos].kind else {
            throw ParserError(message: "Expected metadata key after '#'", location: loc)
        }
        pos += 1
        guard pos < tokens.count, tokens[pos].kind == .colon else {
            throw ParserError(message: "Expected ':' after metadata key", location: tokens[pos].location)
        }
        pos += 1
        // Collect all tokens until newline or end as the metadata value
        var valueParts: [String] = []
        while pos < tokens.count {
            switch tokens[pos].kind {
            case .newline:
                break
            case .identifier(let word):
                valueParts.append(word)
                pos += 1
                continue
            case .numberLiteral(let n):
                valueParts.append(n == n.rounded() ? String(Int(n)) : String(n))
                pos += 1
                continue
            case .stringLiteral(let s):
                valueParts.append(s)
                pos += 1
                continue
            default:
                break
            }
            break
        }
        let value = valueParts.joined(separator: " ")
        guard !value.isEmpty else {
            throw ParserError(message: "Expected metadata value", location: loc)
        }
        return .metadata(key: key, value: value, location: loc)
    }

    // MARK: - Variable Declaration

    private func parseVariableDeclaration(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        let isConstant = tokens[pos].kind == .letKeyword
        pos += 1 // skip let/var
        guard pos < tokens.count, case .identifier(let name) = tokens[pos].kind else {
            throw ParserError(message: "Expected variable name", location: loc)
        }
        pos += 1
        guard pos < tokens.count, tokens[pos].kind == .equals else {
            throw ParserError(message: "Expected '=' in variable declaration", location: tokens[pos].location)
        }
        pos += 1
        let value = try parseExpression(&pos)
        return .variableDeclaration(name: name, value: value, isConstant: isConstant, location: loc)
    }

    // MARK: - Action Call: actionName(param: value) -> output

    private func parseActionCall(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        guard case .identifier(let firstName) = tokens[pos].kind else {
            throw ParserError(message: "Expected action name", location: loc)
        }
        pos += 1

        // Support dotted names for raw 3rd party identifiers (e.g. com.openai.chat.AskIntent)
        var name = firstName
        while pos + 1 < tokens.count,
              tokens[pos].kind == .dot,
              case .identifier(let next) = tokens[pos + 1].kind {
            name += "." + next
            pos += 2
        }

        // Parse arguments
        var arguments: [(label: String?, value: Expression)] = []
        if pos < tokens.count && tokens[pos].kind == .leftParen {
            pos += 1 // skip (
            while pos < tokens.count && tokens[pos].kind != .rightParen {
                skipNewlines(&pos)
                if tokens[pos].kind == .rightParen { break }

                // Check for label: value
                var label: String? = nil
                if case .identifier(let l) = tokens[pos].kind,
                   pos + 1 < tokens.count && tokens[pos + 1].kind == .colon {
                    label = l
                    pos += 2 // skip label and colon
                }

                let value = try parseExpression(&pos)
                arguments.append((label: label, value: value))

                if pos < tokens.count && tokens[pos].kind == .comma {
                    pos += 1
                }
            }
            guard pos < tokens.count, tokens[pos].kind == .rightParen else {
                throw ParserError(message: "Expected ')' after arguments", location: tokens[pos].location)
            }
            pos += 1 // skip )
        }

        // Parse optional output: -> variableName
        var output: String? = nil
        skipNewlines(&pos)
        if pos < tokens.count && tokens[pos].kind == .arrow {
            pos += 1 // skip ->
            skipNewlines(&pos)
            guard pos < tokens.count, case .identifier(let outputName) = tokens[pos].kind else {
                throw ParserError(message: "Expected output variable name after '->'", location: tokens[pos].location)
            }
            output = outputName
            pos += 1
        }

        return .actionCall(name: name, arguments: arguments, output: output, location: loc)
    }

    // MARK: - If Statement

    private func parseIf(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip 'if'
        let condition = try parseCondition(&pos)

        guard pos < tokens.count, tokens[pos].kind == .leftBrace else {
            throw ParserError(message: "Expected '{' after if condition", location: tokens[pos].location)
        }
        let thenBody = try parseBlock(&pos)

        var elseBody: [ASTNode]? = nil
        skipNewlines(&pos)
        if pos < tokens.count && tokens[pos].kind == .elseKeyword {
            pos += 1
            skipNewlines(&pos)
            guard pos < tokens.count, tokens[pos].kind == .leftBrace else {
                throw ParserError(message: "Expected '{' after else", location: tokens[pos].location)
            }
            elseBody = try parseBlock(&pos)
        }

        return .ifStatement(condition: condition, thenBody: thenBody, elseBody: elseBody, location: loc)
    }

    // MARK: - Repeat Loop

    private func parseRepeat(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip 'repeat'
        let count = try parseExpression(&pos)
        guard pos < tokens.count, tokens[pos].kind == .leftBrace else {
            throw ParserError(message: "Expected '{' after repeat count", location: tokens[pos].location)
        }
        let body = try parseBlock(&pos)
        return .repeatLoop(count: count, body: body, location: loc)
    }

    // MARK: - For Each Loop

    private func parseForEach(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip 'for'
        guard pos < tokens.count, case .identifier(let itemName) = tokens[pos].kind else {
            throw ParserError(message: "Expected item name after 'for'", location: loc)
        }
        pos += 1
        guard pos < tokens.count, tokens[pos].kind == .inKeyword else {
            throw ParserError(message: "Expected 'in' after item name", location: tokens[pos].location)
        }
        pos += 1
        let collection = try parseExpression(&pos)
        guard pos < tokens.count, tokens[pos].kind == .leftBrace else {
            throw ParserError(message: "Expected '{' after collection", location: tokens[pos].location)
        }
        let body = try parseBlock(&pos)
        return .forEachLoop(itemName: itemName, collection: collection, body: body, location: loc)
    }

    // MARK: - Menu

    private func parseMenu(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip 'menu'
        guard pos < tokens.count, case .stringLiteral(let title) = tokens[pos].kind else {
            throw ParserError(message: "Expected menu title string", location: tokens[pos].location)
        }
        pos += 1
        skipNewlines(&pos)
        guard pos < tokens.count, tokens[pos].kind == .leftBrace else {
            throw ParserError(message: "Expected '{' after menu title", location: tokens[pos].location)
        }
        pos += 1 // skip {

        var cases: [(label: String, body: [ASTNode])] = []
        while pos < tokens.count && tokens[pos].kind != .rightBrace {
            skipNewlines(&pos)
            if tokens[pos].kind == .rightBrace { break }

            guard tokens[pos].kind == .caseKeyword else {
                throw ParserError(message: "Expected 'case' in menu", location: tokens[pos].location)
            }
            pos += 1
            guard pos < tokens.count, case .stringLiteral(let label) = tokens[pos].kind else {
                throw ParserError(message: "Expected case label string", location: tokens[pos].location)
            }
            pos += 1
            guard pos < tokens.count, tokens[pos].kind == .colon else {
                throw ParserError(message: "Expected ':' after case label", location: tokens[pos].location)
            }
            pos += 1

            var body: [ASTNode] = []
            skipNewlines(&pos)
            while pos < tokens.count && tokens[pos].kind != .caseKeyword && tokens[pos].kind != .rightBrace {
                skipNewlines(&pos)
                if tokens[pos].kind == .caseKeyword || tokens[pos].kind == .rightBrace { break }
                body.append(try parseStatement(&pos))
                skipNewlines(&pos)
            }
            cases.append((label: label, body: body))
        }
        guard pos < tokens.count, tokens[pos].kind == .rightBrace else {
            throw ParserError(message: "Expected '}' to close menu", location: tokens[pos].location)
        }
        pos += 1
        return .menu(title: title, cases: cases, location: loc)
    }

    // MARK: - Function

    private func parseFunction(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1 // skip 'func'
        guard pos < tokens.count, case .identifier(let name) = tokens[pos].kind else {
            throw ParserError(message: "Expected function name", location: loc)
        }
        pos += 1
        guard pos < tokens.count, tokens[pos].kind == .leftParen else {
            throw ParserError(message: "Expected '(' after function name", location: tokens[pos].location)
        }
        pos += 1
        guard pos < tokens.count, tokens[pos].kind == .rightParen else {
            throw ParserError(message: "Expected ')' (parameters not yet supported)", location: tokens[pos].location)
        }
        pos += 1
        guard pos < tokens.count, tokens[pos].kind == .leftBrace else {
            throw ParserError(message: "Expected '{' after function declaration", location: tokens[pos].location)
        }
        let body = try parseBlock(&pos)
        return .functionDeclaration(name: name, body: body, location: loc)
    }

    // MARK: - Return

    private func parseReturn(_ pos: inout Int) throws -> ASTNode {
        let loc = tokens[pos].location
        pos += 1
        skipNewlines(&pos)
        if pos < tokens.count && tokens[pos].kind != .rightBrace && tokens[pos].kind != .eof {
            let value = try parseExpression(&pos)
            return .returnStatement(value: value, location: loc)
        }
        return .returnStatement(value: nil, location: loc)
    }

    // MARK: - Helpers

    private func parseBlock(_ pos: inout Int) throws -> [ASTNode] {
        guard tokens[pos].kind == .leftBrace else {
            throw ParserError(message: "Expected '{'", location: tokens[pos].location)
        }
        pos += 1 // skip {
        var body: [ASTNode] = []
        while pos < tokens.count && tokens[pos].kind != .rightBrace {
            skipNewlines(&pos)
            if tokens[pos].kind == .rightBrace { break }
            body.append(try parseStatement(&pos))
        }
        guard pos < tokens.count, tokens[pos].kind == .rightBrace else {
            throw ParserError(message: "Expected '}'", location: tokens[pos].location)
        }
        pos += 1 // skip }
        return body
    }

    private func parseExpression(_ pos: inout Int) throws -> Expression {
        let token = tokens[pos]
        switch token.kind {
        case .stringLiteral(let value):
            pos += 1
            // Check for interpolation markers
            if value.contains("\\(") {
                let parts = parseInterpolatedString(value)
                return .interpolatedString(parts: parts)
            }
            return .stringLiteral(value)
        case .numberLiteral(let value):
            pos += 1
            return .numberLiteral(value)
        case .boolLiteral(let value):
            pos += 1
            return .boolLiteral(value)
        case .identifier(let name):
            pos += 1
            return .variableReference(name)
        case .leftBrace:
            // Safe: block-level `{` is always consumed by statement parsers (if, repeat,
            // for-each, menu, func) before reaching parseExpression, so `{` here is
            // unambiguously a dictionary literal.
            return try parseDictionaryLiteral(&pos)
        default:
            throw ParserError(message: "Expected expression, got \(token.kind)", location: token.location)
        }
    }

    private func parseDictionaryLiteral(_ pos: inout Int) throws -> Expression {
        let loc = tokens[pos].location
        pos += 1 // skip {
        var entries: [DictionaryEntry] = []

        skipNewlines(&pos)
        while pos < tokens.count && tokens[pos].kind != .rightBrace {
            skipNewlines(&pos)
            if tokens[pos].kind == .rightBrace { break }

            // Parse key (string literal or identifier)
            let key: Expression
            switch tokens[pos].kind {
            case .stringLiteral(let s):
                key = .stringLiteral(s)
                pos += 1
            case .identifier(let name):
                key = .stringLiteral(name)
                pos += 1
            default:
                throw ParserError(message: "Expected dictionary key (string or identifier)", location: tokens[pos].location)
            }

            guard pos < tokens.count, tokens[pos].kind == .colon else {
                throw ParserError(message: "Expected ':' after dictionary key", location: tokens[pos].location)
            }
            pos += 1 // skip :
            skipNewlines(&pos)

            let value = try parseExpression(&pos)
            entries.append(DictionaryEntry(key: key, value: value))

            skipNewlines(&pos)
            if pos < tokens.count && tokens[pos].kind == .comma {
                pos += 1
                skipNewlines(&pos)
            }
        }
        guard pos < tokens.count, tokens[pos].kind == .rightBrace else {
            throw ParserError(message: "Expected '}' to close dictionary literal", location: loc)
        }
        pos += 1 // skip }
        return .dictionaryLiteral(entries)
    }

    private func parseCondition(_ pos: inout Int) throws -> Condition {
        let left = try parseExpression(&pos)

        let token = tokens[pos]
        switch token.kind {
        case .doubleEquals:
            pos += 1
            let right = try parseExpression(&pos)
            return .equals(left: left, right: right)
        case .notEquals:
            pos += 1
            let right = try parseExpression(&pos)
            return .notEquals(left: left, right: right)
        case .greaterThan:
            pos += 1
            let right = try parseExpression(&pos)
            return .greaterThan(left: left, right: right)
        case .lessThan:
            pos += 1
            let right = try parseExpression(&pos)
            return .lessThan(left: left, right: right)
        case .containsKeyword:
            pos += 1
            let right = try parseExpression(&pos)
            return .contains(left: left, right: right)
        default:
            throw ParserError(message: "Expected comparison operator", location: token.location)
        }
    }

    private func parseInterpolatedString(_ value: String) -> [StringPart] {
        var parts: [StringPart] = []
        var current = ""
        var i = value.startIndex

        while i < value.endIndex {
            if value[i] == "\\" && value.index(after: i) < value.endIndex && value[value.index(after: i)] == "(" {
                if !current.isEmpty {
                    parts.append(.text(current))
                    current = ""
                }
                i = value.index(i, offsetBy: 2) // skip \(
                var varName = ""
                while i < value.endIndex && value[i] != ")" {
                    varName.append(value[i])
                    i = value.index(after: i)
                }
                if i < value.endIndex { i = value.index(after: i) } // skip )
                parts.append(.variable(varName))
            } else {
                current.append(value[i])
                i = value.index(after: i)
            }
        }
        if !current.isEmpty {
            parts.append(.text(current))
        }
        return parts
    }

    private func skipNewlines(_ pos: inout Int) {
        while pos < tokens.count && tokens[pos].kind == .newline {
            pos += 1
        }
    }
}
