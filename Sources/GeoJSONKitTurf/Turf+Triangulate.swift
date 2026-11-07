//
//  Turf+Triangulate.swift
//  GeoJSONKitTurf
//

import Foundation

import GeoJSONKit

extension GeoJSON.Polygon {
  /// Splits the polygon into triangles, taking longitude and latitude as flat coordinates,
  /// as turf.js's `tesselate` does.
  ///
  /// Where a ring crosses itself or a hole, as detailed coastlines can, the triangles still
  /// cover about the right area.
  ///
  /// - Complexity: About O(*n* log *n*), where *n* is the count of positions.
  ///
  /// - Returns: Each three are a triangle's corners, counter-clockwise, as indexes into the
  ///   exterior's positions followed by each interior's. Those count each ring's closing
  ///   position, which is never one of the corners.
  public func triangleIndices() -> [Int] {
    let rings = [exterior] + interiors
    let count = rings.reduce(0) { $0 + $1.positions.count }
    var x: [Double] = [], y: [Double] = [], holeStarts: [Int] = []
    x.reserveCapacity(count)
    y.reserveCapacity(count)
    // Each closing position, and the first one, which it's the same as.
    var closing: [Int: Int] = [:]
    for (index, ring) in rings.enumerated() {
      if index > 0 { holeStarts.append(x.count) }
      let start = x.count
      for position in ring.positions {
        x.append(position.longitude)
        y.append(position.latitude)
      }
      if ring.positions.count > 1, ring.positions.first == ring.positions.last {
        closing[x.count - 1] = start
      }
    }

    var triangles = Earcut.triangulate(x: x, y: y, holeStarts: holeStarts)
    for start in stride(from: 0, to: triangles.count - 2, by: 3) {
      for corner in start..<start + 3 {
        if let first = closing[triangles[corner]] { triangles[corner] = first }
      }
      // Curing where a ring crosses itself can leave one the other way around.
      let a = triangles[start], b = triangles[start + 1], c = triangles[start + 2]
      if (x[b] - x[a]) * (y[c] - y[a]) - (y[b] - y[a]) * (x[c] - x[a]) < 0 {
        triangles.swapAt(start + 1, start + 2)
      }
    }
    return triangles
  }
}

extension GeoJSON.Polygon {
  /// Three corners, counter-clockwise when taking longitude and latitude as flat coordinates.
  public struct Triangle: Hashable {
    public let a: GeoJSON.Position
    public let b: GeoJSON.Position
    public let c: GeoJSON.Position

    public init(a: GeoJSON.Position, b: GeoJSON.Position, c: GeoJSON.Position) {
      self.a = a
      self.b = b
      self.c = c
    }
  }

  /// Splits the polygon into triangles, as ``triangleIndices()`` does, then splits those
  /// until no edge is longer than `maxEdgeDegrees`, taking longitude and latitude as flat
  /// coordinates.
  ///
  /// This is for drawing a fill by projecting each triangle's corners and joining them with
  /// straight lines, which only follows a curved projection where the triangles are small.
  /// It also leaves each triangle that's near the edge of a map, or across its seam, small
  /// enough to leave out or cut there.
  ///
  /// Each edge is split at its middle, from both sides, so a corner never ends up on the side
  /// of a neighbour, which would leave a crack between them once they're projected. Long and
  /// thin triangles from the triangulation are first turned into rounder ones, which take
  /// fewer splits.
  ///
  /// Longitudes can run on past the antimeridian, which keeps a ring that crosses it in
  /// one piece. Corners keep their altitude, and the corners that splitting adds have none.
  ///
  /// - Parameter maxEdgeDegrees: How long an edge can be, in degrees. `.infinity` leaves
  ///   the triangles as ``triangleIndices()`` has them.
  /// - Returns: Triangles that together cover the polygon, but not its interiors.
  public func triangles(maxEdgeDegrees: Double) -> [Triangle] {
    let corners = ([exterior] + interiors).flatMap(\.positions)
    let indices = triangleIndices()
    var triangulated = stride(from: 0, to: indices.count - 2, by: 3).map { (indices[$0], indices[$0 + 1], indices[$0 + 2]) }
    Self.flipToDelaunay(&triangulated, corners: corners, maxEdge: maxEdgeDegrees)

    var triangles: [Triangle] = []
    triangles.reserveCapacity(triangulated.count)
    for (a, b, c) in triangulated {
      Self.refine(corners[a], corners[b], corners[c], maxEdge: maxEdgeDegrees, into: &triangles)
    }
    return triangles
  }

  private static func distance(_ a: GeoJSON.Position, _ b: GeoJSON.Position) -> Double {
    let x = b.longitude - a.longitude, y = b.latitude - a.latitude
    return (x * x + y * y).squareRoot()
  }

  private static func midpoint(_ a: GeoJSON.Position, _ b: GeoJSON.Position) -> GeoJSON.Position {
    GeoJSON.Position(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
  }

  /// Splits on the middle of the longest edge. Any edge that's too long is split at the same
  /// place from both sides, so no triangle's corner ends up on the side of its neighbour.
  private static func refine(_ a: GeoJSON.Position, _ b: GeoJSON.Position, _ c: GeoJSON.Position, maxEdge: Double, into triangles: inout [Triangle]) {
    let ab = distance(a, b), bc = distance(b, c), ca = distance(c, a)
    let longest = max(ab, bc, ca)
    guard longest > maxEdge else {
      triangles.append(Triangle(a: a, b: b, c: c))
      return
    }
    if longest == ab {
      let middle = midpoint(a, b)
      refine(a, middle, c, maxEdge: maxEdge, into: &triangles)
      refine(middle, b, c, maxEdge: maxEdge, into: &triangles)
    } else if longest == bc {
      let middle = midpoint(b, c)
      refine(a, b, middle, maxEdge: maxEdge, into: &triangles)
      refine(a, middle, c, maxEdge: maxEdge, into: &triangles)
    } else {
      let middle = midpoint(c, a)
      refine(a, b, middle, maxEdge: maxEdge, into: &triangles)
      refine(middle, b, c, maxEdge: maxEdge, into: &triangles)
    }
  }

  private typealias Corners = (Int, Int, Int)

  /// Ears are long slivers, which all take a lot of splitting to get small, and flipping
  /// the shared edge of a pair where the other diagonal is shorter gets rid of those.
  private static func flipToDelaunay(_ triangles: inout [Corners], corners: [GeoJSON.Position], maxEdge: Double) {
    // Only around those that get split, as the rest are small enough as they are, and
    // most polygons have none of those.
    func isLong(_ triangle: Corners) -> Bool {
      let a = corners[triangle.0], b = corners[triangle.1], c = corners[triangle.2]
      return max(distance(a, b), distance(b, c), distance(c, a)) > maxEdge
    }
    let long = triangles.filter(isLong)
    guard !long.isEmpty else { return }

    struct Edge: Hashable {
      let low: Int, high: Int
      init(_ a: Int, _ b: Int) { (low, high) = a < b ? (a, b) : (b, a) }
    }
    var sides: [Edge: [Int]] = [:]
    sides.reserveCapacity(triangles.count * 2)
    func edges(_ triangle: Corners) -> [Edge] {
      [Edge(triangle.0, triangle.1), Edge(triangle.1, triangle.2), Edge(triangle.2, triangle.0)]
    }
    for (index, triangle) in triangles.enumerated() {
      for edge in edges(triangle) { sides[edge, default: []].append(index) }
    }

    /// The triangle's corners, starting after the edge, so the first is the one opposite it.
    func opposite(_ triangle: Corners, _ edge: Edge) -> Corners {
      if triangle.0 != edge.low, triangle.0 != edge.high { return triangle }
      if triangle.1 != edge.low, triangle.1 != edge.high { return (triangle.1, triangle.2, triangle.0) }
      return (triangle.2, triangle.0, triangle.1)
    }

    var pending = long.flatMap(edges)
    // A fan needs about as many flips as the square of its size, and this is for one that crosses itself.
    var budget = triangles.count * 200
    while let edge = pending.popLast(), budget > 0 {
      guard let both = sides[edge], both.count == 2 else { continue }
      budget -= 1
      // In counter-clockwise order: c is opposite, then a and b are the shared edge.
      let first = opposite(triangles[both[0]], edge)
      let second = opposite(triangles[both[1]], edge)
      let c = first.0, a = first.1, b = first.2, d = second.0
      let pa = corners[a], pb = corners[b], pc = corners[c], pd = corners[d]
      // The flip has to leave two triangles the right way around, for which the four
      // corners have to be convex.
      guard cross(pc, pa, pd) > 1e-9, cross(pd, pb, pc) > 1e-9 else { continue }
      guard inCircle(pa, pb, pc, pd) > 1e-9 else { continue }

      let replacedFirst = (c, a, d), replacedSecond = (d, b, c)
      for index in both {
        for side in edges(triangles[index]) { sides[side]?.removeAll { $0 == index } }
      }
      triangles[both[0]] = replacedFirst
      triangles[both[1]] = replacedSecond
      for (index, triangle) in [(both[0], replacedFirst), (both[1], replacedSecond)] {
        for side in edges(triangle) {
          sides[side, default: []].append(index)
          if side != Edge(c, d) { pending.append(side) }
        }
      }
    }
  }

  private static func cross(_ a: GeoJSON.Position, _ b: GeoJSON.Position, _ c: GeoJSON.Position) -> Double {
    (b.longitude - a.longitude) * (c.latitude - a.latitude) - (b.latitude - a.latitude) * (c.longitude - a.longitude)
  }

  /// Positive if `d` is inside the circle through the counter-clockwise `a`, `b` and `c`.
  private static func inCircle(_ a: GeoJSON.Position, _ b: GeoJSON.Position, _ c: GeoJSON.Position, _ d: GeoJSON.Position) -> Double {
    let adx = a.longitude - d.longitude, ady = a.latitude - d.latitude
    let bdx = b.longitude - d.longitude, bdy = b.latitude - d.latitude
    let cdx = c.longitude - d.longitude, cdy = c.latitude - d.latitude
    let aSquared = adx * adx + ady * ady, bSquared = bdx * bdx + bdy * bdy, cSquared = cdx * cdx + cdy * cdy
    return aSquared * (bdx * cdy - cdx * bdy) - bSquared * (adx * cdy - cdx * ady) + cSquared * (adx * bdy - bdx * ady)
  }
}
