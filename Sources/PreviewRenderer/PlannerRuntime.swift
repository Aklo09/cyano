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
/// This foundation exposes only a fixed self-test, without filesystem or network bridges.
public final class PlannerRuntime {
    private let context: JSContext

    public init() throws {
        guard let context = JSContext() else { throw PlannerRuntimeError.contextUnavailable }
        guard let script = Bundle.module.url(forResource: "planner", withExtension: "js", subdirectory: "Resources") else {
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
              !report.nodeAvailable, !report.networkAPIAvailable else {
            throw PlannerRuntimeError.invalidResult
        }
        return report
    }

    private func checkException() throws {
        if let exception = context.exception {
            throw PlannerRuntimeError.javascript(exception.toString() ?? "Unknown error")
        }
    }
}
