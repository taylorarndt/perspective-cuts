import Foundation

struct CompilerError: Error, CustomStringConvertible {
    let message: String
    let location: SourceLocation?

    var description: String {
        if let loc = location {
            return "Compile error at \(loc): \(message)"
        }
        return "Compile error: \(message)"
    }
}

struct Compiler: Sendable {
    let registry: ActionRegistry
    let toolKitReader: ToolKitReader?

    init(registry: ActionRegistry, toolKitReader: ToolKitReader? = nil) {
        self.registry = registry
        self.toolKitReader = toolKitReader
    }

    // Track output name -> UUID mapping so variable references use ActionOutput
    private struct OutputRef {
        let uuid: String
        let name: String
    }

    func compile(nodes: [ASTNode]) throws -> [String: Any] {
        var outputMap: [String: OutputRef] = [:]
        return try compileWithOutputMap(nodes: nodes, outputMap: &outputMap)
    }

    private func compileWithOutputMap(nodes: [ASTNode], outputMap: inout [String: OutputRef]) throws -> [String: Any] {
        var actions: [[String: Any]] = []
        var shortcutName = "Perspective Shortcut"
        var iconColor = 463140863 // blue default
        var iconGlyph = 59771 // gear default

        for node in nodes {
            switch node {
            case .importStatement: break // handled at validation
            case .metadata(let key, let value, _):
                if key == "color", let color = registry.iconColors[value] {
                    iconColor = color
                }
                if key == "icon" {
                    // Map common icon names to glyph numbers
                    iconGlyph = iconGlyphNumber(for: value)
                }
                if key == "name" {
                    shortcutName = value
                }
            case .comment(let text, _):
                actions.append(buildAction(
                    identifier: "is.workflow.actions.comment",
                    parameters: ["WFCommentActionText": text]
                ))
            case .variableDeclaration(let name, let value, _, _):
                // Emit the appropriate action based on expression type
                let sourceAction: [String: Any]
                if case .dictionaryLiteral = value {
                    sourceAction = try buildDictionaryAction(from: value, outputMap: outputMap)
                } else {
                    sourceAction = try buildTextAction(from: value, outputMap: outputMap)
                }
                actions.append(sourceAction)
                actions.append(buildAction(
                    identifier: "is.workflow.actions.setvariable",
                    parameters: [
                        "WFVariableName": name,
                        "WFInput": buildMagicVariable(outputOf: sourceAction)
                    ]
                ))
            case .actionCall(let name, let arguments, let output, let location):
                let def = registry.actions[name]
                // If action contains dots, treat as raw identifier (3rd party app action)
                let isThirdParty = def == nil && name.contains(".")
                let identifier: String
                if let def {
                    identifier = def.identifier
                } else if isThirdParty {
                    identifier = name
                } else {
                    var msg = "Unknown action: '\(name)'"
                    if let suggestion = registry.findClosestAction(to: name) {
                        msg += ". Did you mean '\(suggestion)'?"
                    }
                    throw CompilerError(message: msg, location: location)
                }

                // For 3rd-party actions, look up parameter types from the ToolKit DB
                let toolKitParams: [String: ToolKitParameterDetail]? = isThirdParty
                    ? toolKitReader?.getParameterInfo(actionIdentifier: name) : nil

                var params: [String: Any] = [:]
                let uuid = UUID().uuidString
                params["UUID"] = uuid
                if let output {
                    params["CustomOutputName"] = output
                }

                for (label, value) in arguments {
                    if let label {
                        let resolvedValue: Any

                        if isThirdParty {
                            // 3rd-party App Intent action — use ToolKit type info
                            let tkParam = toolKitParams?[label]
                            if tkParam?.isDynamicEntity == true || tkParam?.typeKind == 2 {
                                // Dynamic entity: wrap as { value, title, subtitle }
                                let plainVal = try expressionToPlainValue(value, outputMap: outputMap)
                                let strVal = "\(plainVal)"
                                resolvedValue = [
                                    "value": strVal,
                                    "title": ["key": strVal],
                                    "subtitle": ["key": strVal]
                                ] as [String: Any]
                            } else if tkParam?.typeKind == 3 || tkParam?.typeKind == 4 {
                                // Static enum: use plain value
                                resolvedValue = try expressionToPlainValue(value, outputMap: outputMap)
                            } else {
                                // Primitives (string, int, bool, etc.): use plain values
                                resolvedValue = try expressionToPlainValue(value, outputMap: outputMap)
                            }
                        } else {
                            // Built-in action — use ActionRegistry parameter definitions
                            let paramDef: ActionParameter? = def.flatMap { d in
                                d.parameters[label] ??
                                d.parameters.first(where: { $0.key.caseInsensitiveCompare(label) == .orderedSame })?.value ??
                                d.parameters.first(where: {
                                    let stripped = $0.key.replacingOccurrences(of: "WF", with: "", options: [.anchored, .caseInsensitive])
                                    return stripped.caseInsensitiveCompare(label) == .orderedSame
                                })?.value
                            }

                            if let paramType = paramDef?.type, paramType == "enumInt",
                               let valueMap = paramDef?.valueMap,
                               case .stringLiteral(let s) = value,
                               let intVal = valueMap[s] {
                                resolvedValue = intVal
                            } else if let paramType = paramDef?.type, (paramType == "enum" || paramType == "boolean" || paramType == "plainString") {
                                resolvedValue = try expressionToPlainValue(value, outputMap: outputMap)
                            } else {
                                resolvedValue = try expressionToValueWithOutputMap(value, outputMap: outputMap)
                            }

                            // For built-in actions, map friendly name to plist key
                            let plistKey = paramDef?.key ?? label
                            params[plistKey] = resolvedValue
                            continue
                        }

                        // For 3rd-party actions, use the label directly as the key
                        params[label] = resolvedValue
                    }
                }

                actions.append(buildAction(identifier: identifier, parameters: params))

                // Track output for ActionOutput references
                if let output {
                    outputMap[output] = OutputRef(uuid: uuid, name: output)
                }

            case .ifStatement(let condition, let thenBody, let elseBody, _):
                let groupID = UUID().uuidString
                // Emit conditional start
                var condParams: [String: Any] = ["GroupingIdentifier": groupID, "WFControlFlowMode": 0]
                try applyCondition(condition, to: &condParams, outputMap: outputMap)
                actions.append(buildAction(identifier: "is.workflow.actions.conditional", parameters: condParams))

                // Emit then body
                for bodyNode in thenBody {
                    let compiled = try compileWithOutputMap(nodes: [bodyNode], outputMap: &outputMap)
                    if let bodyActions = compiled["WFWorkflowActions"] as? [[String: Any]] {
                        actions.append(contentsOf: bodyActions)
                    }
                }

                // Emit else branch
                if let elseBody {
                    actions.append(buildAction(
                        identifier: "is.workflow.actions.conditional",
                        parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 1]
                    ))
                    for bodyNode in elseBody {
                        let compiled = try compileWithOutputMap(nodes: [bodyNode], outputMap: &outputMap)
                        if let bodyActions = compiled["WFWorkflowActions"] as? [[String: Any]] {
                            actions.append(contentsOf: bodyActions)
                        }
                    }
                }

                // Emit conditional end
                actions.append(buildAction(
                    identifier: "is.workflow.actions.conditional",
                    parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 2]
                ))

            case .repeatLoop(let count, let body, _):
                let groupID = UUID().uuidString
                let countValue = try expressionToValueWithOutputMap(count, outputMap: outputMap)
                actions.append(buildAction(
                    identifier: "is.workflow.actions.repeat.count",
                    parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 0, "WFRepeatCount": countValue]
                ))
                for bodyNode in body {
                    let compiled = try compileWithOutputMap(nodes: [bodyNode], outputMap: &outputMap)
                    if let bodyActions = compiled["WFWorkflowActions"] as? [[String: Any]] {
                        actions.append(contentsOf: bodyActions)
                    }
                }
                actions.append(buildAction(
                    identifier: "is.workflow.actions.repeat.count",
                    parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 2]
                ))

            case .forEachLoop(_, let collection, let body, _):
                let groupID = UUID().uuidString
                let collectionValue = try expressionToValueWithOutputMap(collection, outputMap: outputMap)
                actions.append(buildAction(
                    identifier: "is.workflow.actions.repeat.each",
                    parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 0, "WFInput": collectionValue]
                ))
                for bodyNode in body {
                    let compiled = try compileWithOutputMap(nodes: [bodyNode], outputMap: &outputMap)
                    if let bodyActions = compiled["WFWorkflowActions"] as? [[String: Any]] {
                        actions.append(contentsOf: bodyActions)
                    }
                }
                actions.append(buildAction(
                    identifier: "is.workflow.actions.repeat.each",
                    parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 2]
                ))

            case .menu(let title, let cases, _):
                let groupID = UUID().uuidString
                let caseLabels = cases.map { $0.label }
                actions.append(buildAction(
                    identifier: "is.workflow.actions.choosefrommenu",
                    parameters: [
                        "GroupingIdentifier": groupID,
                        "WFControlFlowMode": 0,
                        "WFMenuPrompt": title,
                        "WFMenuItems": caseLabels
                    ]
                ))
                for menuCase in cases {
                    actions.append(buildAction(
                        identifier: "is.workflow.actions.choosefrommenu",
                        parameters: [
                            "GroupingIdentifier": groupID,
                            "WFControlFlowMode": 1,
                            "WFMenuItemTitle": menuCase.label
                        ]
                    ))
                    for bodyNode in menuCase.body {
                        let compiled = try compileWithOutputMap(nodes: [bodyNode], outputMap: &outputMap)
                        if let bodyActions = compiled["WFWorkflowActions"] as? [[String: Any]] {
                            actions.append(contentsOf: bodyActions)
                        }
                    }
                }
                actions.append(buildAction(
                    identifier: "is.workflow.actions.choosefrommenu",
                    parameters: ["GroupingIdentifier": groupID, "WFControlFlowMode": 2]
                ))

            case .functionDeclaration, .returnStatement:
                // Functions are inlined at call sites (macro-style for now)
                break
            }
        }

        return [
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowClientVersion": "1200",
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": iconColor,
                "WFWorkflowIconGlyphNumber": iconGlyph
            ],
            "WFWorkflowTypes": ["NCWidget", "WatchKit"],
            "WFWorkflowInputContentItemClasses": [
                "WFAppStoreAppContentItem",
                "WFArticleContentItem",
                "WFContactContentItem",
                "WFDateContentItem",
                "WFEmailAddressContentItem",
                "WFGenericFileContentItem",
                "WFImageContentItem",
                "WFiTunesProductContentItem",
                "WFLocationContentItem",
                "WFDCMapsLinkContentItem",
                "WFAVAssetContentItem",
                "WFPDFContentItem",
                "WFPhoneNumberContentItem",
                "WFRichTextContentItem",
                "WFSafariWebPageContentItem",
                "WFStringContentItem",
                "WFURLContentItem"
            ],
            "WFWorkflowActions": actions,
            "WFWorkflowName": shortcutName
        ]
    }

    // MARK: - Helpers

    private func buildAction(identifier: String, parameters: [String: Any]) -> [String: Any] {
        [
            "WFWorkflowActionIdentifier": identifier,
            "WFWorkflowActionParameters": parameters
        ]
    }

    private func buildDictionaryAction(from expression: Expression, outputMap: [String: OutputRef]) throws -> [String: Any] {
        let value = try expressionToValueWithOutputMap(expression, outputMap: outputMap)
        let uuid = UUID().uuidString
        return buildAction(
            identifier: "is.workflow.actions.dictionary",
            parameters: ["WFItems": value, "UUID": uuid, "CustomOutputName": "Dictionary"]
        )
    }

    private func buildTextAction(from expression: Expression, outputMap: [String: OutputRef] = [:]) throws -> [String: Any] {
        let value = try expressionToValueWithOutputMap(expression, outputMap: outputMap)
        let uuid = UUID().uuidString
        return buildAction(
            identifier: "is.workflow.actions.gettext",
            parameters: ["WFTextActionText": value, "UUID": uuid]
        )
    }

    private func buildMagicVariable(outputOf action: [String: Any]) -> [String: Any] {
        let params = action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]
        let uuid = params["UUID"] as? String ?? UUID().uuidString
        return [
            "Value": [
                "OutputUUID": uuid,
                "Type": "ActionOutput",
                "OutputName": params["CustomOutputName"] ?? "Text"
            ],
            "WFSerializationType": "WFTextTokenAttachment"
        ]
    }

    private func expressionToPlainValue(_ expr: Expression, outputMap: [String: OutputRef] = [:]) throws -> Any {
        switch expr {
        case .stringLiteral(let s): return s
        case .numberLiteral(let n): return n == n.rounded() ? Int(n) : n
        case .boolLiteral(let b): return b
        case .dictionaryLiteral: return try expressionToValueWithOutputMap(expr, outputMap: outputMap)
        default: return try expressionToValueWithOutputMap(expr, outputMap: outputMap)
        }
    }

    private func expressionToValueWithOutputMap(_ expr: Expression, outputMap: [String: OutputRef]) throws -> Any {
        switch expr {
        case .stringLiteral(let s):
            return [
                "Value": ["string": s, "attachmentsByRange": [String: Any]()],
                "WFSerializationType": "WFTextTokenString"
            ] as [String: Any]
        case .numberLiteral(let n): return n == n.rounded() ? Int(n) : n
        case .boolLiteral(let b): return b
        case .variableReference(let name):
            // Use WFTextTokenString with attachmentsByRange -- this is how Apple's own shortcuts pass variables
            if let ref = outputMap[name] {
                return [
                    "Value": [
                        "string": "\u{FFFC}",
                        "attachmentsByRange": [
                            "{0, 1}": [
                                "OutputName": ref.name,
                                "OutputUUID": ref.uuid,
                                "Type": "ActionOutput"
                            ]
                        ]
                    ],
                    "WFSerializationType": "WFTextTokenString"
                ] as [String: Any]
            }
            return [
                "Value": [
                    "string": "\u{FFFC}",
                    "attachmentsByRange": [
                        "{0, 1}": ["VariableName": name, "Type": "Variable"]
                    ]
                ],
                "WFSerializationType": "WFTextTokenString"
            ] as [String: Any]
        case .interpolatedString(let parts):
            var text = ""
            var attachments: [String: Any] = [:]
            for part in parts {
                switch part {
                case .text(let t):
                    text += t
                case .variable(let name):
                    let pos = text.count
                    text += "\u{FFFC}"
                    let range = "{\(pos), 1}"
                    if let ref = outputMap[name] {
                        attachments[range] = [
                            "OutputName": ref.name,
                            "OutputUUID": ref.uuid,
                            "Type": "ActionOutput"
                        ]
                    } else {
                        attachments[range] = ["VariableName": name, "Type": "Variable"]
                    }
                }
            }
            return [
                "Value": ["string": text, "attachmentsByRange": attachments],
                "WFSerializationType": "WFTextTokenString"
            ] as [String: Any]
        case .dictionaryLiteral(let entries):
            var items: [[String: Any]] = []
            for entry in entries {
                var item: [String: Any] = [:]
                item["WFKey"] = try expressionToValueWithOutputMap(entry.key, outputMap: outputMap)

                switch entry.value {
                case .numberLiteral(let n):
                    item["WFItemType"] = 3
                    let s = n == n.rounded() ? String(Int(n)) : String(n)
                    item["WFValue"] = [
                        "Value": ["string": s, "attachmentsByRange": [String: Any]()],
                        "WFSerializationType": "WFTextTokenString"
                    ] as [String: Any]
                case .boolLiteral(let b):
                    item["WFItemType"] = 4
                    item["WFValue"] = [
                        "Value": b,
                        "WFSerializationType": "WFNumberSubstitutableState"
                    ] as [String: Any]
                case .dictionaryLiteral:
                    item["WFItemType"] = 1
                    item["WFValue"] = try expressionToValueWithOutputMap(entry.value, outputMap: outputMap)
                default:
                    item["WFItemType"] = 0
                    item["WFValue"] = try expressionToValueWithOutputMap(entry.value, outputMap: outputMap)
                }
                items.append(item)
            }
            return [
                "Value": ["WFDictionaryFieldValueItems": items],
                "WFSerializationType": "WFDictionaryFieldValue"
            ] as [String: Any]
        }
    }

    private func applyCondition(_ condition: Condition, to params: inout [String: Any], outputMap: [String: OutputRef]) throws {
        // Helper: resolve the left-hand side of a condition.
        // Conditionals use a nested format for WFInput:
        //   { Type: "Variable", Variable: { Value: { ... }, WFSerializationType: "WFTextTokenAttachment" } }
        func resolveInput(_ expr: Expression) throws -> Any {
            if case .variableReference(let name) = expr {
                let inner: [String: Any]
                if let ref = outputMap[name] {
                    inner = [
                        "Value": [
                            "OutputUUID": ref.uuid,
                            "Type": "ActionOutput",
                            "OutputName": ref.name
                        ],
                        "WFSerializationType": "WFTextTokenAttachment"
                    ] as [String: Any]
                } else {
                    inner = [
                        "Value": ["VariableName": name, "Type": "Variable"],
                        "WFSerializationType": "WFTextTokenAttachment"
                    ] as [String: Any]
                }
                return [
                    "Type": "Variable",
                    "Variable": inner
                ] as [String: Any]
            }
            return try expressionToValueWithOutputMap(expr, outputMap: outputMap)
        }

        switch condition {
        case .equals(let left, let right):
            params["WFInput"] = try resolveInput(left)
            params["WFCondition"] = 4 // equals
            params["WFConditionalActionString"] = try expressionToValueWithOutputMap(right, outputMap: outputMap)
        case .notEquals(let left, let right):
            params["WFInput"] = try resolveInput(left)
            params["WFCondition"] = 5 // not equals
            params["WFConditionalActionString"] = try expressionToValueWithOutputMap(right, outputMap: outputMap)
        case .contains(let left, let right):
            params["WFInput"] = try resolveInput(left)
            params["WFCondition"] = 99 // contains
            params["WFConditionalActionString"] = try expressionToValueWithOutputMap(right, outputMap: outputMap)
        case .greaterThan(let left, let right):
            params["WFInput"] = try resolveInput(left)
            params["WFCondition"] = 2 // greater than
            params["WFConditionalActionString"] = try expressionToValueWithOutputMap(right, outputMap: outputMap)
        case .lessThan(let left, let right):
            params["WFInput"] = try resolveInput(left)
            params["WFCondition"] = 3 // less than
            params["WFConditionalActionString"] = try expressionToValueWithOutputMap(right, outputMap: outputMap)
        }
    }

    private func iconGlyphNumber(for name: String) -> Int {
        let glyphs: [String: Int] = [
            "gear": 59771, "compose": 59772, "star": 59773,
            "heart": 59774, "bolt": 59775, "globe": 59776,
            "mic": 59777, "music": 59778, "play": 59779,
            "camera": 59780, "photo": 59781, "film": 59782,
            "mail": 59783, "message": 59784, "phone": 59785,
            "clock": 59786, "alarm": 59787, "calendar": 59788,
            "map": 59789, "location": 59790, "bookmark": 59791,
            "tag": 59792, "folder": 59793, "doc": 59794,
            "list": 59795, "cart": 59796, "bag": 59797,
            "gift": 59798, "lock": 59799, "key": 59800,
            "link": 59801, "flag": 59802, "bell": 59803,
            "eye": 59804, "hand": 59805, "person": 59806,
            "house": 59807, "car": 59808, "airplane": 59809,
            "sun": 59810, "moon": 59811, "cloud": 59812,
            "umbrella": 59813, "flame": 59814, "drop": 59815,
            "leaf": 59816, "paintbrush": 59817, "pencil": 59818,
            "scissors": 59819, "wand": 59820, "cube": 59821,
            "download": 59822, "upload": 59823, "share": 59824,
            "trash": 59825, "magnifyingglass": 59826
        ]
        return glyphs[name.lowercased()] ?? 59771
    }
}
