import Foundation

import GeoJSONKit

extension GeoJSON.Geometry {
  public func contains(_ coordinate: GeoJSON.Position, ignoreBoundary: Bool = false, checkBoundingBox: Bool = true) -> Bool {
    switch self {
    case .polygon(let polygon):
      return polygon.contains(coordinate, ignoreBoundary: ignoreBoundary, checkBoundingBox: checkBoundingBox)
    case .lineString, .point:
      return false
    }
  }
  
  /// Calculates the absolute centre (of the bounding box).
  public func center() -> GeoJSON.Position? {
    switch self {
    case .point(let position):
      return position
    case .lineString(let line):
      return GeoJSON.BoundingBox(positions: line.positions).center
    case .polygon(let polygon):
      return GeoJSON.BoundingBox(positions: polygon.exterior.positions).center
    }
  }
  
  /// Calculates the centroid using the mean of all vertices.
  /// This lessens the effect of small islands and artifacts when calculating the centroid of a set of polygons.
  public func centroid() -> GeoJSON.Position? {
    switch self {
    case .point(let position):
      return position
    case .lineString(let line):
      let length = line.distance() ?? 0
      return line.coordinateFromStart(distance: length / 2)
    case .polygon(let polygon):
      let positions = polygon.exterior.positions.dropLast()
      let summed = positions
        .reduce(into: GeoJSON.Position(latitude: 0, longitude: 0)) { acc, next in
          acc.latitude += next.latitude
          acc.longitude += next.longitude
        }
      return GeoJSON.Position(
        latitude: summed.latitude / Double(positions.count),
        longitude: summed.longitude / Double(positions.count)
      ).normalized
    }
  }
  
  /// Calculates the [center of mass](https://en.wikipedia.org/wiki/Center_of_mass) using this formula: [Centroid of Polygon](https://en.wikipedia.org/wiki/Centroid#Centroid_of_polygon).
  public func centerOfMass() -> GeoJSON.Position? {
    guard case .polygon(let polygon) = self else {
      return centroid() // no difference
    }
    
    // First, we neutralize the feature (set it around coordinates [0,0]) to prevent rounding errors
    // We take any point to translate all the points around 0
    guard let center = centroid() else { return nil }
    let positions = polygon.exterior.positions
    let neutralized = positions.map {
      GeoJSON.Position(latitude: $0.latitude - center.latitude, longitude: $0.longitude - center.longitude)
    }
    
    var signedArea: Double = 0
    var sum = GeoJSON.Position(latitude: 0, longitude: 0)
    let zipped = zip(neutralized.prefix(upTo: neutralized.count - 1), neutralized.suffix(from: 1))
    for (pi, pj) in zipped {
      let (xi, yi) = (pi.longitude, pi.latitude)
      let (xj, yj) = (pj.longitude, pj.latitude)
      
      // common factor to compute the signed area and the final coordinates
      let a = xi * yj - xj * yi
      signedArea += a
      sum.longitude += (xi + xj) * a
      sum.latitude += (yi + yj) * a
    }
    guard signedArea != 0 else { return center }
    
    // compute signed area, and factorise 1/6A
    let area = signedArea / 2
    let areaFactor = 1 / (6 * area)
    
    // final coordinates, adding back values that have been neutralized
    return GeoJSON.Position(
      latitude: center.latitude + areaFactor * sum.latitude,
      longitude: center.longitude + areaFactor * sum.longitude
    ).normalized
  }
  
  /// Finds the nearest position on the geometry that's closest to the provided position.
  public func nearestPoint(to position: GeoJSON.Position) -> GeoJSON.Position? {
    switch self {
    case .point(let point):
      return point
    case .lineString(let line):
      return line.closestCoordinate(to: position)?.coordinate
    case .polygon(let polygon):
      return polygon.nearestPoint(to: position)
    }
  }

}

extension GeoJSON.GeometryObject {

  /**
   * Determines if the given coordinate falls within any of the polygons.
   * The optional parameter `ignoreBoundary` will result in the method returning true if the given coordinate
   * lies on the boundary line of the polygon or its interior rings.
   *
   * Calls contains function for each contained polygon
   */
  public func contains(_ coordinate: GeoJSON.Position, ignoreBoundary: Bool = false, checkBoundingBox: Bool = true) -> Bool {
    switch self {
    case .single(let geometry):
      return geometry.contains(coordinate, ignoreBoundary: ignoreBoundary, checkBoundingBox: checkBoundingBox)
    case .multi(let geometries):
      return geometries.contains(where: { $0.contains(coordinate, ignoreBoundary: ignoreBoundary, checkBoundingBox: checkBoundingBox) })
    case .collection(let objects):
      return objects.contains(where: { $0.contains(coordinate, ignoreBoundary: ignoreBoundary, checkBoundingBox: checkBoundingBox) })
    }
  }

}

// MARK: - Anti-meridian safety

extension GeoJSON.Geometry {
  
  func breakUpIfNecessary() -> [GeoJSON.Geometry] {
    let bbox = GeoJSON.BoundingBox(positions: positions, allowSpanningAntimeridian: true)
    guard bbox.spansAntimeridian else {
      return [self]
    }
    
    let normalized = self.wrapped(min: 0, max: 360)
    
    // Western-most point to anti-meridian
    // No need to wrap, as already positive
    let easterlyBox = GeoJSON.BoundingBox(positions: [
      .init(latitude: bbox.northEasterlyLatitude, longitude: 180),
      .init(latitude: bbox.southWesterlyLatitude, longitude: bbox.southWesterlyLongitude)
    ])
    
    // Anti-meridian to eastern-mode point
    // This needs to be wrapped sa the clipping doesn't work otherwise
    let westerlyBox = GeoJSON.BoundingBox(positions: [
      .init(latitude: bbox.northEasterlyLatitude, longitude: bbox.northEasterlyLongitude.wrap(min: 0, max: 360)),
      .init(latitude: bbox.southWesterlyLatitude, longitude: 180)
    ])
    
    let easterly = normalized.clipped(to: easterlyBox)
    let westerly = normalized.clipped(to: westerlyBox)
    return [
      easterly,
      westerly.wrapped(min: -180, max: 180),
    ]
  }
  
  private func clipped(to bbox: GeoJSON.BoundingBox) -> GeoJSON.Geometry {
    switch self {
    case .point:
      return self
    case .lineString(let line):
      return .lineString(line.clipped(to: bbox))
    case .polygon(let polygon):
      return .polygon(polygon.clipped(to: bbox))
    }
  }
  
  private func wrapped(min: GeoJSON.Degrees, max: GeoJSON.Degrees) -> GeoJSON.Geometry {
    switch self {
    case .point:
      return self
      
    case .lineString(let line):
      let normalized = line.positions.map {
        GeoJSON.Position(latitude: $0.latitude, longitude: $0.longitude.wrap(min: min, max: max))
      }
      return .lineString(.init(positions: normalized))

    case .polygon(let polygon):
      let normalized = polygon.exterior.positions.map {
        GeoJSON.Position(latitude: $0.latitude, longitude: $0.longitude.wrap(min: min, max: max))
      }
      return .polygon(.init(exterior: .init(positions: normalized)))
    }
  }
}


extension GeoJSON.GeometryObject {
  
  /// Checks the provided geometry, if it crosses the anti-meridian. If it doesn't, it's returned as
  /// a `.single`, otherwise it's broken up into two and returned as a `.multi`.
  ///
  /// - Parameter candidate: A geometry, which might cross the anti-meridian
  public init(splittingWhenCrossingAntiMeridian candidate: GeoJSON.Geometry) {
    let components = candidate.breakUpIfNecessary()
    if components.count == 1, let only = components.first {
      self = .single(only)
    } else {
      self = .multi(components)
    }
  }
}
