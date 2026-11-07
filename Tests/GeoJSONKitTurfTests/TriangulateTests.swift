//
//  TriangulateTests.swift
//  GeoJSONKitTurf
//

#if canImport(Testing) && compiler(>=6)
import Foundation
import Testing

import GeoJSONKit
import GeoJSONKitTurf

struct TriangulateTests {
  private static func polygon(_ rings: [[(x: Double, y: Double)]]) -> GeoJSON.Polygon {
    GeoJSON.Polygon(rings.map { ring in ring.map { GeoJSON.Position(latitude: $0.y, longitude: $0.x) } })
  }

  /// The corners, in the order that `triangleIndices()` counts them.
  private static func corners(of polygon: GeoJSON.Polygon) -> [GeoJSON.Position] {
    polygon.exterior.positions + polygon.interiors.flatMap(\.positions)
  }

  private static func cross(_ a: GeoJSON.Position, _ b: GeoJSON.Position, _ c: GeoJSON.Position) -> Double {
    (b.longitude - a.longitude) * (c.latitude - a.latitude) - (b.latitude - a.latitude) * (c.longitude - a.longitude)
  }

  /// Checks that the triangles are counter-clockwise, and adds up their area.
  private static func area(of polygon: GeoJSON.Polygon, sourceLocation: SourceLocation = #_sourceLocation) -> Double {
    let indices = polygon.triangleIndices()
    #expect(indices.count % 3 == 0, sourceLocation: sourceLocation)
    let corners = corners(of: polygon)
    var total = 0.0
    for start in stride(from: 0, to: indices.count - 2, by: 3) {
      let twice = cross(corners[indices[start]], corners[indices[start + 1]], corners[indices[start + 2]])
      #expect(twice >= 0, sourceLocation: sourceLocation)
      total += twice / 2
    }
    return total
  }

  private static let square = [(x: 0.0, y: 0.0), (10, 0), (10, 10), (0, 10), (0, 0)]

  @Test func square() {
    let polygon = Self.polygon([Self.square])
    #expect(polygon.triangleIndices().count == 6)
    #expect(abs(Self.area(of: polygon) - 100) < 1e-9)
  }

  @Test func clockwise() {
    let polygon = Self.polygon([Self.square.reversed()])
    #expect(abs(Self.area(of: polygon) - 100) < 1e-9)
  }

  @Test func concave() {
    let polygon = Self.polygon([[(0, 0), (40, 0), (40, 10), (10, 10), (10, 40), (0, 40), (0, 0)]])
    #expect(polygon.triangleIndices().count == 4 * 3)
    #expect(abs(Self.area(of: polygon) - 700) < 1e-9)
  }

  @Test func holes() {
    let polygon = Self.polygon([
      [(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)],
      [(5, 5), (5, 15), (15, 15), (15, 5), (5, 5)],
      [(25, 25), (35, 25), (35, 35), (25, 35), (25, 25)],
    ])
    #expect(abs(Self.area(of: polygon) - 1400) < 1e-9)
    // Nothing in the holes.
    let corners = Self.corners(of: polygon)
    let indices = polygon.triangleIndices()
    for start in stride(from: 0, to: indices.count, by: 3) {
      let triangle = indices[start..<start + 3].map { corners[$0] }
      let x = triangle.reduce(0) { $0 + $1.longitude } / 3, y = triangle.reduce(0) { $0 + $1.latitude } / 3
      #expect(!(5...15).contains(x) || !(5...15).contains(y))
      #expect(!(25...35).contains(x) || !(25...35).contains(y))
    }
  }

  /// Detailed data has the odd tiny hole that's just outside, which has nothing to cut out.
  @Test func holesOutside() {
    for hole in [[(45.0, 18.0), (45, 22), (47, 22), (47, 18), (45, 18)], [(-3, 18), (-3, 22), (-1, 22), (-1, 18), (-3, 18)]] {
      let polygon = Self.polygon([[(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)], hole])
      #expect(abs(Self.area(of: polygon) - 1600) < 1e-9)
    }
  }

  @Test func leavesOutClosingPositions() {
    let polygon = Self.polygon([
      [(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)],
      [(10, 10), (10, 20), (20, 20), (20, 10), (10, 10)],
    ])
    let indices = Set(polygon.triangleIndices())
    #expect(indices == Set([0, 1, 2, 3, 5, 6, 7, 8]))
  }

  @Test func tooFewCorners() {
    #expect(Self.polygon([[(0, 0), (1, 1), (0, 0)]]).triangleIndices().isEmpty)
    #expect(Self.polygon([[]]).triangleIndices().isEmpty)
  }

  /// Detailed coastlines go across themselves in tiny loops, which shouldn't stop the rest
  /// from being filled.
  @Test func crossingItself() {
    let polygon = Self.polygon([[
      (0, 0), (19.9, 0), (20.1, -0.3), (19.9, -0.3), (20.1, 0),
      (40, 0), (40, 19.9), (40.3, 20.1), (40.3, 19.9), (40, 20.1),
      (40, 40), (20.1, 40), (19.9, 40.3), (20.1, 40.3), (19.9, 40),
      (0, 40), (0, 20.1), (-0.3, 19.9), (-0.3, 20.1), (0, 19.9), (0, 0),
    ]])
    #expect(abs(Self.area(of: polygon) - 1600) < 1)
  }

  /// Starting in the smaller loop, which is what ends up deciding which way around it goes.
  @Test func figureOfEight() {
    let polygon = Self.polygon([[(-1, -1), (-10, -1), (-10, 1), (-1, 1), (1, -1), (21, -1), (21, 1), (1, 1), (-1, -1)]])
    #expect(abs(Self.area(of: polygon) - 62) < 1e-9)
  }

  /// Large enough that the corners get sorted along a curve, and jagged like a coastline,
  /// so that most of them are reflex.
  @Test func manyCorners() {
    let count = 20_000
    let ring = (0...count).map { step -> (x: Double, y: Double) in
      let angle = Double(step % count) / Double(count) * 2 * .pi
      let radius = step % 2 == 0 ? 10.0 : 9.998
      return (radius * cos(angle), radius * sin(angle))
    }
    let polygon = Self.polygon([ring])
    var expected = 0.0
    for index in 0..<count {
      expected += ring[index].x * ring[index + 1].y - ring[index + 1].x * ring[index].y
    }
    #expect(polygon.triangleIndices().count == (count - 2) * 3)
    #expect(abs(Self.area(of: polygon) - expected / 2) < 1e-6)
  }
}

#endif
