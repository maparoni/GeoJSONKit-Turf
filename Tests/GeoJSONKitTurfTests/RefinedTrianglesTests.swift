//
//  RefinedTrianglesTests.swift
//  GeoJSONKitTurf
//

#if canImport(Testing) && compiler(>=6)
import Foundation
import Testing

import GeoJSONKit
import GeoJSONKitTurf

struct RefinedTrianglesTests {
  private static func polygon(_ rings: [[(x: Double, y: Double)]]) -> GeoJSON.Polygon {
    GeoJSON.Polygon(rings.map { ring in ring.map { GeoJSON.Position(latitude: $0.y, longitude: $0.x) } })
  }

  private static func cross(_ a: GeoJSON.Position, _ b: GeoJSON.Position, _ c: GeoJSON.Position) -> Double {
    (b.longitude - a.longitude) * (c.latitude - a.latitude) - (b.latitude - a.latitude) * (c.longitude - a.longitude)
  }

  private static func distance(_ a: GeoJSON.Position, _ b: GeoJSON.Position) -> Double {
    hypot(b.longitude - a.longitude, b.latitude - a.latitude)
  }

  static let cases: [(String, [[(x: Double, y: Double)]], Double)] = [
    ("square", [[(10, 10), (40, 10), (40, 30), (10, 30), (10, 10)]], 600),
    ("the other way around", [[(10, 10), (10, 30), (40, 30), (40, 10), (10, 10)]], 600),
    ("concave", [[(0, 0), (40, 0), (40, 10), (10, 10), (10, 40), (0, 40), (0, 0)]], 700),
    ("with a hole", [[(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)], [(10, 10), (10, 20), (20, 20), (20, 10), (10, 10)]], 1500),
    ("with two holes", [[(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)], [(5, 5), (5, 15), (15, 15), (15, 5), (5, 5)], [(25, 25), (25, 35), (35, 35), (35, 25), (25, 25)]], 1400),
    // Longitudes can run on past the antimeridian, which keeps a ring that crosses it in one piece.
    ("past the antimeridian", [[(170, -10), (190, -10), (190, 10), (170, 10), (170, -10)]], 400),
    // As Antarctica's ring is: along the coast, then along the south pole and back.
    ("to the south pole and back", [stride(from: -180.0, through: 180.0, by: 20).map { ($0, -70) } + [(180, -90), (-180, -90), (-180, -70)]], 7200),
    // Detailed coastlines go across themselves in tiny loops.
    ("with sides that cross themselves", [[
      (0, 0), (19.9, 0), (20.1, -0.3), (19.9, -0.3), (20.1, 0),
      (40, 0), (40, 19.9), (40.3, 20.1), (40.3, 19.9), (40, 20.1),
      (40, 40), (20.1, 40), (19.9, 40.3), (20.1, 40.3), (19.9, 40),
      (0, 40), (0, 20.1), (-0.3, 19.9), (-0.3, 20.1), (0, 19.9), (0, 0),
    ]], 1600),
    // And they're rounded, so that those loops can start and end on the very same corner.
    ("with sides that go through their own corners", [[
      (0, 0), (20, 0), (20.1, -0.3), (19.9, -0.3), (20, 0),
      (40, 0), (40, 20), (40.3, 20.1), (40.3, 19.9), (40, 20),
      (40, 40), (20, 40), (19.9, 40.3), (20.1, 40.3), (20, 40),
      (0, 40), (0, 20), (-0.3, 19.9), (-0.3, 20.1), (0, 20), (0, 0),
    ]], 1600),
    ("with a hole beyond it", [[(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)], [(-3, 18), (-1, 18), (-1, 22), (-3, 22), (-3, 18)]], 1600),
    ("a figure of eight", [[(-1, -1), (-10, -1), (-10, 1), (-1, 1), (1, -1), (21, -1), (21, 1), (1, 1), (-1, -1)]], 62),
  ]

  @Test("Triangles add up to the polygon, turn the same way and stay small", arguments: cases)
  func addUp(name: String, rings: [[(x: Double, y: Double)]], area: Double) {
    let triangles = Self.polygon(rings).triangles(maxEdgeDegrees: 10)
    var total = 0.0
    var longest = 0.0
    for triangle in triangles {
      let twice = Self.cross(triangle.a, triangle.b, triangle.c)
      #expect(twice >= 0)
      total += twice / 2
      longest = max(longest, Self.distance(triangle.a, triangle.b), Self.distance(triangle.b, triangle.c), Self.distance(triangle.c, triangle.a))
    }
    #expect(abs(total - area) < 0.001 * area)
    #expect(longest <= 10)
  }

  /// Each edge that's split is split from both sides, so no corner ends up on the side of a
  /// neighbour, which would leave a crack where the two are drawn after projecting them. What
  /// only one triangle has is then the polygon's outline, which adds up to its perimeter.
  @Test func noCornerOnASide() {
    let polygon = Self.polygon([
      [(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)],
      [(10, 10), (10, 20), (20, 20), (20, 10), (10, 10)],
    ])
    struct Edge: Hashable {
      let from: GeoJSON.Position, to: GeoJSON.Position
    }
    var edges: [Edge: Int] = [:]
    for triangle in polygon.triangles(maxEdgeDegrees: 3) {
      for (from, to) in [(triangle.a, triangle.b), (triangle.b, triangle.c), (triangle.c, triangle.a)] {
        // Counter-clockwise, so a neighbour has the same edge the other way around.
        if let count = edges[Edge(from: to, to: from)] {
          edges[Edge(from: to, to: from)] = count == 1 ? nil : count - 1
        } else {
          edges[Edge(from: from, to: to), default: 0] += 1
        }
      }
    }
    let outline = edges.reduce(0.0) { $0 + Self.distance($1.key.from, $1.key.to) * Double($1.value) }
    #expect(abs(outline - (160 + 40)) < 1e-9)
  }

  @Test func unrefined() {
    let polygon = Self.polygon([
      [(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)],
      [(10, 10), (10, 20), (20, 20), (20, 10), (10, 10)],
    ])
    let positions = polygon.exterior.positions + polygon.interiors.flatMap(\.positions)
    let indices = polygon.triangleIndices()
    let expected = stride(from: 0, to: indices.count, by: 3).map {
      GeoJSON.Polygon.Triangle(a: positions[indices[$0]], b: positions[indices[$0 + 1]], c: positions[indices[$0 + 2]])
    }
    #expect(polygon.triangles(maxEdgeDegrees: .infinity) == expected)
  }

  /// Ears along a strip with many corners are long slivers to its far side, which take a lot
  /// of splitting to get small. Flipping them first leaves a zigzag across it instead.
  @Test func fewTriangles() {
    let bottom = (0...100).map { (x: Double($0), y: 0.0) }
    let top = (0...100).reversed().map { (x: Double($0), y: 10.0) }
    let triangles = Self.polygon([bottom + top + [bottom[0]]]).triangles(maxEdgeDegrees: 10)
    // Each of the zigzag's 200 has a diagonal that's just too long, so takes a split. Without
    // the flips it's more than ten times as many.
    #expect(triangles.count == 400)
  }

  static let wrappingCases: [(String, [[(x: Double, y: Double)]], Double)] = [
    ("across the antimeridian", [[(170, -10), (-170, -10), (-170, 10), (170, 10), (170, -10)]], 400),
    ("a hole across the antimeridian", [[(160, -20), (-160, -20), (-160, 20), (160, 20), (160, -20)], [(170, -10), (170, 10), (-170, 10), (-170, -10), (170, -10)]], 1200),
    ("a hole a turn away", [[(170, -10), (190, -10), (190, 10), (170, 10), (170, -10)], [(-185, -5), (-185, 5), (-175, 5), (-175, -5), (-185, -5)]], 300),
    ("around the south pole", [stride(from: -180.0, through: 180.0, by: 20).map { ($0, -70) }], 7200),
    ("around the north pole", [stride(from: 180.0, through: -180.0, by: -20).map { ($0, 70) }], 7200),
    // It starts on a peninsula with a bay to its south, as Antarctica's ring does, which
    // can't go straight to the pole.
    ("around the south pole, from over a bay", [[(0, -60), (20, -70)] + stride(from: 60.0, to: 340, by: 30).map { ($0, -70) } + [(-20, -70), (-10, -85), (5, -80), (0, -60)]], 7037.5),
    ("to the south pole and back", [stride(from: -180.0, through: 180.0, by: 20).map { ($0, -70) } + [(180, -90), (-180, -90), (-180, -70)]], 7200),
    ("neither", [[(10, 10), (40, 10), (40, 30), (10, 30), (10, 10)]], 600),
  ]

  @Test("Unwrapped rings add up to the polygon", arguments: wrappingCases)
  func unwrapped(name: String, rings: [[(x: Double, y: Double)]], area: Double) {
    let unwrapped = Self.polygon(rings).unwrapped()
    for ring in [unwrapped.exterior] + unwrapped.interiors {
      #expect(ring.positions.first == ring.positions.last)
      for (from, to) in zip(ring.positions, ring.positions.dropFirst()) {
        // Other than along a pole.
        #expect(abs(to.longitude - from.longitude) <= 180 || (abs(from.latitude) == 90 && to.latitude == from.latitude))
      }
    }
    let total = unwrapped.triangles(maxEdgeDegrees: 10).reduce(0.0) { $0 + Self.cross($1.a, $1.b, $1.c) / 2 }
    #expect(abs(total - area) < 0.001 * area)
  }

  @Test func unwrappedKeepsWhatDoesNotWrap() {
    let polygon = Self.polygon([[(10, 10), (40, 10), (40, 30), (10, 30), (10, 10)], [(15, 15), (15, 20), (20, 20), (20, 15), (15, 15)]])
    #expect(polygon.unwrapped().positionsArray == polygon.positionsArray)
  }

  @Test func tooFewCorners() {
    #expect(Self.polygon([[(0, 0), (1, 1), (0, 0)]]).triangles(maxEdgeDegrees: 1).isEmpty)
    #expect(Self.polygon([[]]).triangles(maxEdgeDegrees: 1).isEmpty)
  }
}

#endif
