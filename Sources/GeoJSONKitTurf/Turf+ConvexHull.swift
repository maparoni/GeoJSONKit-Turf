//
//  Turf+ConvexHull.swift
//  
//
//  Created by Adrian Schönig on 14/6/2022.
//

import Foundation

import GeoJSONKit

extension Collection where Element == GeoJSON.Position {
  /// Calculate the convex hull of a given sequence of positions.
  ///
  /// - Complexity: O(*n* log *n*), where *n* is the count of `points`.
  ///
  /// - Returns: The convex hull of this sequence as a polygon
  public func convexHull() -> GeoJSON.Polygon {
    let positions = AndrewsMonotoneChain.convexHull(self)
    return .init(exterior: .init(positions: positions))
  }
}
