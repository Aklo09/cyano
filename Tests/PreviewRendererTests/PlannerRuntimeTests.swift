import Foundation
import Testing

@testable import PreviewRenderer

/// A render database with only inserters and the two indication sprites; no private artwork.
private let inserterDatabase = """
    {"schema":2,"atlases":[{"file":"a","w":64,"h":64}],
     "frames":[{"a":0,"x":0,"y":0,"w":64,"h":64,"ox":0,"oy":0,"sw":64,"sh":64},
               {"a":0,"x":0,"y":0,"w":64,"h":64,"ox":0,"oy":0,"sw":64,"sh":64}],
     "icons":{"utility/indication-line":0,"utility/indication-arrow":1},
     "iconScales":{"utility/indication-line":0.5,"utility/indication-arrow":0.5},
     "tiles":{},
     "entities":{
       "inserter":{"kind":"inserter","protoType":"inserter","graphics":[],
         "collisionBox":[[-0.15,-0.15],[0.15,0.15]],"selectionBox":[[-0.4,-0.35],[0.4,0.45]],
         "data":{"pickupPosition":[0,-1],"insertPosition":[0,1.2]}},
       "long-handed-inserter":{"kind":"inserter","protoType":"inserter","graphics":[],
         "collisionBox":[[-0.15,-0.15],[0.15,0.15]],"selectionBox":[[-0.4,-0.35],[0.4,0.45]],
         "data":{"pickupPosition":[0,-2],"insertPosition":[0,2.2]}}}}
    """

private struct Marker: Equatable {
    let frame: Int, x: Double, y: Double, rotation: Double
}

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

    @Test("Alt mode marks inserter pickup with a line and drop with an arrow, rotated with the entity")
    func inserterIndications() throws {
        // Version 2.0: 16-way directions (4 east, 8 south, 12 west).
        let entry = """
            {"blueprint":{"item":"blueprint","version":562949954076673,"entities":[
              {"entity_number":1,"name":"inserter","position":{"x":0.5,"y":0.5}},
              {"entity_number":2,"name":"inserter","position":{"x":2.5,"y":0.5},"direction":4},
              {"entity_number":3,"name":"inserter","position":{"x":4.5,"y":0.5},"direction":8},
              {"entity_number":4,"name":"inserter","position":{"x":6.5,"y":0.5},"direction":12},
              {"entity_number":5,"name":"long-handed-inserter","position":{"x":8.5,"y":0.5}}]}}
            """
        let planned = try PlannerRuntime().plan(entry: Data(entry.utf8), database: Data(inserterDatabase.utf8))
        var markers: [Int: [Marker]] = [:]
        for command in planned.drawList.commands where command.kind == "icon" {
            markers[Int(command.entity), default: []].append(
                Marker(
                    frame: try #require(command.frame), x: try #require(command.x), y: try #require(command.y),
                    rotation: command.rotation ?? 0))
            #expect(command.size == 0.75)
        }
        let line = 0
        let arrow = 1
        #expect(
            markers[1] == [
                Marker(frame: line, x: 0.5, y: -0.3, rotation: 0), Marker(frame: arrow, x: 0.5, y: 1.3, rotation: 180),
            ])
        #expect(
            markers[2] == [
                Marker(frame: line, x: 3.3, y: 0.5, rotation: 90), Marker(frame: arrow, x: 1.7, y: 0.5, rotation: 270),
            ])
        #expect(
            markers[3] == [
                Marker(frame: line, x: 4.5, y: 1.3, rotation: 180), Marker(frame: arrow, x: 4.5, y: -0.3, rotation: 0),
            ])
        #expect(
            markers[4] == [
                Marker(frame: line, x: 5.7, y: 0.5, rotation: 270), Marker(frame: arrow, x: 7.3, y: 0.5, rotation: 90),
            ])
        #expect(
            markers[5] == [
                Marker(frame: line, x: 8.5, y: -1.3, rotation: 0), Marker(frame: arrow, x: 8.5, y: 2.3, rotation: 180),
            ])
    }

    @Test("Inserter indications are omitted when the release lacks the line sprite")
    func inserterIndicationsNeedSprites() throws {
        let database = inserterDatabase.replacingOccurrences(of: "\"utility/indication-line\":0,", with: "")
        let entry = """
            {"blueprint":{"item":"blueprint","version":562949954076673,"entities":[
              {"entity_number":1,"name":"inserter","position":{"x":0.5,"y":0.5}}]}}
            """
        let planned = try PlannerRuntime().plan(entry: Data(entry.utf8), database: Data(database.utf8))
        #expect(planned.drawList.commands.filter { $0.kind == "icon" }.isEmpty)
    }
}
