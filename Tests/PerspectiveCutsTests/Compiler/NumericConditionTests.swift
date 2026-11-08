import Foundation
import Testing
@testable import perspective_cuts

struct NumericConditionTests {
    // Exercise both operators and thresholds on either side of ten. These tests
    // verify serialization; the companion fixture verifies branch execution.
    @Test(arguments: [">", "<"], ["5", "50", "2.5"])
    func literalOperands(comparison: String, threshold: String) throws {
        let params = try compileCondition(comparison: comparison, right: threshold)
        #expect(params["WFNumberValue"] as? String == threshold)
    }

    @Test(arguments: [">", "<"], ["5", "50"])
    func actionOutputOperands(comparison: String, threshold: String) throws {
        let params = try compileCondition(
            setup: "number(value: \(threshold)) -> limit",
            comparison: comparison, right: "limit"
        )
        let token = try #require(params["WFNumberValue"] as? [String: Any])
        #expect(token["WFSerializationType"] as? String == "WFTextTokenString")
        let tokenValue = try #require(token["Value"] as? [String: Any])
        #expect(tokenValue["string"] as? String == "\u{FFFC}")
        let attachments = try #require(tokenValue["attachmentsByRange"] as? [String: Any])
        #expect(attachments.count == 1)
        let value = try #require(attachments["{0, 1}"] as? [String: Any])
        #expect(value["Type"] as? String == "ActionOutput")
        #expect(value["OutputName"] as? String == "limit")
        #expect(UUID(uuidString: try #require(value["OutputUUID"] as? String)) != nil)
    }

    @Test(arguments: [">", "<"])
    func namedVariableOperands(comparison: String) throws {
        let params = try compileCondition(
            setup: #"var limit = "5""#, comparison: comparison, right: "limit"
        )
        let token = try #require(params["WFNumberValue"] as? [String: Any])
        #expect(token["WFSerializationType"] as? String == "WFTextTokenString")
        let tokenValue = try #require(token["Value"] as? [String: Any])
        #expect(tokenValue["string"] as? String == "\u{FFFC}")
        let attachments = try #require(tokenValue["attachmentsByRange"] as? [String: Any])
        #expect(attachments.count == 1)
        let value = try #require(attachments["{0, 1}"] as? [String: Any])
        #expect(value["Type"] as? String == "Variable")
        #expect(value["VariableName"] as? String == "limit")
    }

    @Test(arguments: [">", "<"], ["5", "50"])
    func interpolatedOperands(comparison: String, threshold: String) throws {
        let params = try compileCondition(
            setup: "number(value: \(threshold)) -> limit",
            comparison: comparison, right: #""\(limit)""#
        )
        let token = try #require(params["WFNumberValue"] as? [String: Any])
        #expect(token["WFSerializationType"] as? String == "WFTextTokenString")
        let value = try #require(token["Value"] as? [String: Any])
        #expect(value["string"] as? String == "\u{FFFC}")
        let attachments = try #require(value["attachmentsByRange"] as? [String: Any])
        let attachment = try #require(attachments["{0, 1}"] as? [String: Any])
        #expect(attachment["Type"] as? String == "ActionOutput")
        #expect(attachment["OutputName"] as? String == "limit")
        #expect(UUID(uuidString: try #require(attachment["OutputUUID"] as? String)) != nil)
    }

    private func compileCondition(
        setup: String = "", comparison: String, right: String
    ) throws -> [String: Any] {
        let source = """
        number(value: 10) -> ten
        \(setup)
        if ten \(comparison) \(right) {
            text(text: "yes")
        } else {
            text(text: "no")
        }
        """
        let nodes = try Parser(tokens: Lexer(source: source).tokenize()).parse()
        let plist = try Compiler(registry: ActionRegistry.load()).compile(nodes: nodes)
        // Round-trip the actual generated binary plist, not just the in-memory value.
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let decoded = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let actions = try #require(decoded["WFWorkflowActions"] as? [[String: Any]])
        let condition = try #require(actions.first {
            $0["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.conditional"
        })
        let params = try #require(condition["WFWorkflowActionParameters"] as? [String: Any])
        #expect(params["WFCondition"] as? Int == (comparison == ">" ? 2 : 0))
        #expect(params["WFConditionalActionString"] == nil)
        let input = try #require(params["WFInput"] as? [String: Any])
        let variable = try #require(input["Variable"] as? [String: Any])
        let value = try #require(variable["Value"] as? [String: Any])
        let aggrandizements = try #require(value["Aggrandizements"] as? [[String: Any]])
        #expect(aggrandizements.first?["CoercionItemClass"] as? String == "WFNumberContentItem")
        return params
    }
}
