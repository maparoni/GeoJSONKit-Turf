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
