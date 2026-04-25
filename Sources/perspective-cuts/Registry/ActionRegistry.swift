import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct ActionParameter: Sendable {
    let type: String
    let required: Bool
    let key: String
    let values: [String]?
    let valueMap: [String: Int]?

    init(type: String, required: Bool, key: String, values: [String]? = nil, valueMap: [String: Int]? = nil) {
        self.type = type
        self.required = required
        self.key = key
        self.values = values
        self.valueMap = valueMap
    }
}

struct ActionDefinition: Sendable {
    let identifier: String
    let description: String
    let parameters: [String: ActionParameter]
}

struct ActionRegistry: Sendable {
    let actions: [String: ActionDefinition]
    let controlFlow: [String: String] // name -> WFWorkflowActionIdentifier
    let iconColors: [String: Int]

    static func load() throws -> ActionRegistry {
        let data: Data

        // Try multiple locations for actions.json
        let candidates: [URL] = {
            var urls: [URL?] = []

            // SwiftPM resource bundle when built from source.
            urls.append(Bundle.module.url(forResource: "actions", withExtension: "json"))

            // Use _NSGetExecutablePath + realpath to find the true binary location.
            // CommandLine.arguments[0] is often a bare name like "perspective-cuts" when
            // run from PATH, which resolves against CWD instead of the actual binary.
            let execDir: URL = {
                #if canImport(Darwin)
                var bufsize: UInt32 = 0
                _NSGetExecutablePath(nil, &bufsize)
                var buf = [CChar](repeating: 0, count: Int(bufsize))
                _NSGetExecutablePath(&buf, &bufsize)
                var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
                if realpath(&buf, &resolved) != nil {
                    return URL(fileURLWithPath: String(cString: resolved)).deletingLastPathComponent()
                }
                #endif
                return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            }()

            // 1. Next to executable
            urls.append(execDir.appendingPathComponent("actions.json"))

            // 2. Homebrew Cellar layout: <prefix>/bin/perspective-cuts -> <prefix>/Resources/actions.json
            urls.append(execDir.deletingLastPathComponent().appendingPathComponent("Resources/actions.json"))

            // 3. SPM resource bundle (swift run in development)
            urls.append(execDir.appendingPathComponent("perspective-cuts_perspective-cuts.bundle/actions.json"))

            // 4. Bundle.main fallback
            if let bundleURL = Bundle.main.url(forResource: "actions", withExtension: "json", subdirectory: nil) {
                urls.append(bundleURL)
            }

            return urls.compactMap { $0 }
        }()

        var foundData: Data?
        for url in candidates {
            if let d = try? Data(contentsOf: url) {
                foundData = d
                break
            }
        }

        guard let loaded = foundData else {
            throw RegistryError(message: "Could not find actions.json. Searched: \(candidates.map(\.path).joined(separator: ", "))")
        }
        data = loaded
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        var actions: [String: ActionDefinition] = [:]
        if let actionsDict = json["actions"] as? [String: [String: Any]] {
            for (name, def) in actionsDict {
                let identifier = def["identifier"] as? String ?? ""
                let description = def["description"] as? String ?? ""
                var params: [String: ActionParameter] = [:]
                if let paramsDict = def["parameters"] as? [String: [String: Any]] {
                    for (paramName, paramDef) in paramsDict {
                        params[paramName] = ActionParameter(
                            type: paramDef["type"] as? String ?? "string",
                            required: paramDef["required"] as? Bool ?? false,
                            key: paramDef["key"] as? String ?? paramName,
                            values: paramDef["values"] as? [String],
                            valueMap: paramDef["values"] as? [String: Int]
                        )
                    }
                }
                actions[name] = ActionDefinition(identifier: identifier, description: description, parameters: params)
            }
        }

        var controlFlow: [String: String] = [:]
        if let cfDict = json["controlFlow"] as? [String: [String: Any]] {
            for (name, def) in cfDict {
                controlFlow[name] = def["identifier"] as? String
            }
        }

        var iconColors: [String: Int] = [:]
        if let colorDict = json["iconColors"] as? [String: Int] {
            iconColors = colorDict
        }

        return ActionRegistry(actions: actions, controlFlow: controlFlow, iconColors: iconColors)
    }

    func findClosestAction(to name: String) -> String? {
        let lowered = name.lowercased()
        var bestMatch: String? = nil
        var bestDistance = Int.max
        for key in actions.keys {
            let dist = levenshteinDistance(lowered, key.lowercased())
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = key
            }
        }
        return bestDistance <= 3 ? bestMatch : nil
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dist[i][j] = min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + cost)
            }
        }
        return dist[a.count][b.count]
    }
}

struct RegistryError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
