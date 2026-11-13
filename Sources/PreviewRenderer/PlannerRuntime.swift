import Foundation
import JavaScriptCore

public enum PlannerRuntimeError: Error, CustomStringConvertible {
    case resourceMissing
    case contextUnavailable
    case javascript(String)
    case invalidResult

    public var description: String {
        switch self {
        case .resourceMissing: "The bundled planner resource is missing."
        case .contextUnavailable: "JavaScriptCore could not create an execution context."
        case .javascript(let message): "Planner JavaScript failed: \(message)"
        case .invalidResult: "The planner returned an invalid self-test result."
        }
    }
}

public struct PlannerSelfTest: Codable, Sendable {
    public let schema: Int
    public let plannerRevision: String
    public let upgradeCommands: Int
    public let deconstructionCommands: Int
    public let finiteBounds: Bool
    public let nodeAvailable: Bool
    public let networkAPIAvailable: Bool
}

/// Synchronous, thread-confined runtime. Production jobs will run in a helper process.
/// No filesystem or network bridges are installed in JavaScriptCore.
public final class PlannerRuntime {
    private let context: JSContext

    public init() throws {
        guard let context = JSContext() else { throw PlannerRuntimeError.contextUnavailable }
        guard let script = Bundle.module.url(forResource: "planner", withExtension: "js", subdirectory: "Resources")
        else {
            throw PlannerRuntimeError.resourceMissing
        }
        self.context = context
        context.evaluateScript(try String(contentsOf: script, encoding: .utf8), withSourceURL: script)
        try checkException()
    }

    public func selfTest() throws -> PlannerSelfTest {
        context.exception = nil
        let result = context.evaluateScript("JSON.stringify(FBPlanner.selfTest())")
        try checkException()
        guard let json = result?.toString(), let data = json.data(using: .utf8) else {
            throw PlannerRuntimeError.invalidResult
        }
        let report = try JSONDecoder().decode(PlannerSelfTest.self, from: data)
        guard report.schema == 1, report.finiteBounds,
            !report.nodeAvailable, !report.networkAPIAvailable
        else {
            throw PlannerRuntimeError.invalidResult
        }
        return report
    }

    func plan(entry: Data, database: Data) throws -> PlannedPreview {
        guard let entryJSON = String(data: entry, encoding: .utf8),
            let dbJSON = String(data: database, encoding: .utf8),
            let function = context.objectForKeyedSubscript("FBPlanner")?.objectForKeyedSubscript("nativePlan")
        else { throw PlannerRuntimeError.invalidResult }
        context.exception = nil
        let value = function.call(withArguments: [entryJSON, dbJSON])
        try checkException()
        guard let json = value?.toString(), json.utf8.count <= 64 * 1024 * 1024,
            let bytes = json.data(using: .utf8)
        else { throw PlannerRuntimeError.invalidResult }
        let result = try JSONDecoder().decode(PlannedPreview.self, from: bytes)
        guard result.schema == 1, result.drawList.schema == 1, result.drawList.commands.count <= 250_000,
            result.warnings.count <= 100_000
        else { throw PreviewError.invalidDrawList }
        try result.drawList.bounds.validate()
        return result
    }

    private func checkException() throws {
        if let exception = context.exception {
            throw PlannerRuntimeError.javascript(exception.toString() ?? "Unknown error")
        }
    }
}
