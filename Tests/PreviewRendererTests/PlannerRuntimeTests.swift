import PreviewRenderer
import Testing

@Suite("JavaScriptCore planner foundation")
struct PlannerRuntimeTests {
    @Test("Pinned planner executes without Node or network bridges")
    func plannerLoadsAndRuns() throws {
        let result = try PlannerRuntime().selfTest()
        #expect(result.plannerRevision == "2f7dc70f2681de530402556f757006e904e692d5")
        #expect(result.upgradeCommands == 0)
        #expect(result.deconstructionCommands == 0)
        #expect(result.finiteBounds)
        #expect(!result.nodeAvailable)
        #expect(!result.networkAPIAvailable)
    }

    @Test("Independent contexts have the same deterministic result")
    func independentContexts() throws {
        let first = try PlannerRuntime().selfTest()
        let second = try PlannerRuntime().selfTest()
        #expect(first.plannerRevision == second.plannerRevision)
        #expect(first.upgradeCommands == second.upgradeCommands)
        #expect(first.deconstructionCommands == second.deconstructionCommands)
    }
}
