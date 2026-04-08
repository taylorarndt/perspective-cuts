import Foundation

enum ASTNode: Sendable {
    case importStatement(module: String, location: SourceLocation)
    case metadata(key: String, value: String, location: SourceLocation)
    case comment(text: String, location: SourceLocation)

    case variableDeclaration(name: String, value: Expression, isConstant: Bool, location: SourceLocation)

    case actionCall(name: String, arguments: [(label: String?, value: Expression)], output: String?, location: SourceLocation)

    case ifStatement(condition: Condition, thenBody: [ASTNode], elseBody: [ASTNode]?, location: SourceLocation)

    case repeatLoop(count: Expression, body: [ASTNode], location: SourceLocation)
    case forEachLoop(itemName: String, collection: Expression, body: [ASTNode], location: SourceLocation)

    case menu(title: String, cases: [(label: String, body: [ASTNode])], location: SourceLocation)

    case functionDeclaration(name: String, body: [ASTNode], location: SourceLocation)
    case returnStatement(value: Expression?, location: SourceLocation)
}

struct DictionaryEntry: Sendable {
    let key: Expression
    let value: Expression
}

enum Expression: Sendable {
    case stringLiteral(String)
    case numberLiteral(Double)
    case boolLiteral(Bool)
    case variableReference(String)
    case interpolatedString(parts: [StringPart])
    case dictionaryLiteral([DictionaryEntry])
}

enum StringPart: Sendable {
    case text(String)
    case variable(String)
}

enum Condition: Sendable {
    case equals(left: Expression, right: Expression)
    case notEquals(left: Expression, right: Expression)
    case contains(left: Expression, right: Expression)
    case greaterThan(left: Expression, right: Expression)
    case lessThan(left: Expression, right: Expression)
}
