import Foundation

import GeoJSONKit

extension GeoJSON.Polygon {
  
  /**
   Initializes a polygon as a given center coordinate with a given number of
   vertices, as a means to approximate a circle.
   
   - Parameter center: The center coordinate for the polygon.
   - Parameter radius: The radius of the polygon, measured in meters.
   - Parameter vertices: The number of vertices the polygon will have.
   The recommended and default amount is 64.
   - Returns: A polygon shape which approximates a circle.
   */
  public init(center: GeoJSON.Position, radius: GeoJSON.Distance, vertices: Int = 64) {
    // The first and last coordinates in a polygon must be identical,
    // which is why we're using the inclusive range operator in this case.
    // Ported from https://github.com/Turfjs/turf/blob/17002ccd57e04e84ddb38d7e3ac8ede35b019c58/packages/turf-circle/index.ts
    let positions = (0...vertices).map { ( step ) -> GeoJSON.Position in
      let bearing = fabs(GeoJSON.Direction(step * -360 / vertices))
      return center.coordinate(at: radius, facing: bearing)
    }
    
    self.init([positions])
  }
  
  var coordinates: [[GeoJSON.Position]] { positionsArray }
  
  /// An area of current `.Polygon`
  ///
  /// Ported from https://github.com/Turfjs/turf/blob/a94151418cb969868fdb42955a19a133512da0fd/packages/turf-area/index.js
  public var area: Double {
    return abs(exterior.area) - interiors
      .map { abs($0.area) }
      .reduce(0, +)
  }
  
  /// Determines if the given coordinate falls within the polygon and outside of its interior rings.
  /// The optional parameter `ignoreBoundary` will result in the method returning true if the given coordinate
  /// lies on the boundary line of the polygon or its interior rings.
  ///
  ///Ported from: https://github.com/Turfjs/turf/blob/e53677b0931da9e38bb947da448ee7404adc369d/packages/turf-boolean-point-in-polygon/index.ts#L31-L75
  public func contains(_ position: GeoJSON.Position, ignoreBoundary: Bool = false, checkBoundingBox: Bool = true) -> Bool {
    guard exterior.contains(position, ignoreBoundary: ignoreBoundary, checkBoundingBox: checkBoundingBox) else {
      return false
    }
    for ring in interiors {
      if ring.contains(position, ignoreBoundary: !ignoreBoundary, checkBoundingBox: false) {
        return false
      }
    }
    return true
  }
  
  /// Finds the nearest position on the polygon that's closest to the provided position.
  ///
  /// If the provided point is contained by the polygon
  public func nearestPoint(to position: GeoJSON.Position) -> GeoJSON.Position? {
    if !exterior.contains(position, ignoreBoundary: false) {
      return exterior.closestPosition(to: position)
    }
    
    if let inner = interiors.first(where: { $0.contains(position, ignoreBoundary: false) }) {
      return inner.closestPosition(to: position)
    }
    
    // The exterior contains it, but none of the interiors do
    // => The point is within the polygon
    return position
  }
}

// MARK: - Polygon.clip(_:)

extension GeoJSON.Polygon {
  
  /// Clips a `.Polygon` to a bounding box
  ///
  /// Ported from https://github.com/Turfjs/turf/blob/master/packages/turf-bbox-clip/index.ts
  public func clip(to boundingBox: GeoJSON.BoundingBox) -> GeoJSON.Polygon {
    var rings: [GeoJSON.Polygon.LinearRing] = []
    for ring in [exterior] + interiors {
      var clip: GeoJSON.Polygon.LinearRing = ring.clip(to: boundingBox)
      if let first = clip.positions.first {
        if first != clip.positions.last {
          clip.positions.append(first)
        }
        if clip.positions.count >= 4 {
          rings.append(clip)
        }
      }
    }
    return .init(rings.map(\.positions))
  }
  
}

extension GeoJSON.Polygon.LinearRing {
  // Sutherland-Hodgeman polygon clipping algorithm
  func clip(to boundingBox: GeoJSON.BoundingBox) -> GeoJSON.Polygon.LinearRing {
    var result = [GeoJSON.Position]()
    var prev: GeoJSON.Position
    var prevInside: Bool
    var inside: Bool
    var points = positions
    
    for edge in [1, 2, 4, 8] {
      result = []
      prev = points.last!
      prevInside = !(bitCode(p: prev, bbox: boundingBox) & edge != 0)
      
      for point in points {
        inside = !(bitCode(p: point, bbox: boundingBox) & edge != 0)
        
        if inside != prevInside {
          if let intersection = intersect(a: prev, b: point, edge: edge, bbox: boundingBox) {
            result.append(intersection)
          }
        }
        
        if inside {
          result.append(point)
        }
        
        prev = point
        prevInside = inside
      }
      
      points = result
      if result.isEmpty {
        break
      }
    }
    
    return .init(positions: result)
  }
  
  private func intersect(a: GeoJSON.Position, b: GeoJSON.Position, edge: Int, bbox: GeoJSON.BoundingBox) -> GeoJSON.Position? {
    if edge & 8 != 0 {
      return .init(x: a.x + ((b.x - a.x) * (bbox.top - a.y)) / (b.y - a.y), y: bbox.top)
    } else if edge & 4 != 0 {
      return .init(x: a.x + ((b.x - a.x) * (bbox.bottom - a.y)) / (b.y - a.y), y: bbox.bottom)
    } else if edge & 2 != 0 {
      return .init(x: bbox.right, y: a.y + ((b.y - a.y) * (bbox.right - a.x)) / (b.x - a.x))
    } else if edge & 1 != 0 {
      return .init(x: bbox.left, y: a.y + ((b.y - a.y) * (bbox.left - a.x)) / (b.x - a.x))
    } else {
      return nil
    }
  }
  
  private func bitCode(p: GeoJSON.Position, bbox: GeoJSON.BoundingBox) -> Int {
    var code = 0
    
    if p.x < bbox.left {
      code |= 1
    } else if p.x > bbox.right {
      code |= 2
    }
    
    if p.y < bbox.bottom {
      code |= 4
    } else if p.y > bbox.top {
      code |= 8
    }
    
    return code
  }
}

fileprivate extension GeoJSON.BoundingBox {
  var left: Double { southWesterlyLongitude }
  var right: Double { northEasterlyLongitude }
  var top: Double { northEasterlyLatitude }
  var bottom: Double { southWesterlyLatitude }
}

fileprivate extension GeoJSON.Position {
  var x: Double { longitude }
  var y: Double { latitude }
  
  init(x: Double, y: Double) {
    self.init(latitude: y, longitude: x)
  }
}

// MARK: - Polygon.smooth()

extension GeoJSON.Polygon {
  
  /// Smooths a `.Polygon`. Based on [Chaikin's algorithm](http://graphics.cs.ucdavis.edu/education/CAGDNotes/Chaikins-Algorithm/Chaikins-Algorithm.html).
  /// Warning: may create degenerate polygons.
  ///
  /// Ported from https://github.com/Turfjs/turf/blob/402716a29f6ae16bf3d0220e213e5380cc5a50c4/packages/turf-polygon-smooth/index.js
  public func smooth(iterations: Int = 3) -> GeoJSON.Polygon {
    var poly = self
    var tempOutput: [[GeoJSON.Position]] = [[]];
    var outCoords: [[GeoJSON.Position]] = [[]];
    
    (0..<iterations).forEach({ i in
      tempOutput = [[]]
      
      if (i > 0) {
        poly = GeoJSON.Polygon(outCoords);
      }
      
      processPolygon(poly, &tempOutput);
      outCoords = tempOutput
    })
    
    return GeoJSON.Polygon(outCoords);
  }
  
  private func processPolygon(_ poly: GeoJSON.Polygon, _ tempOutput: inout [[GeoJSON.Position]]) {
    var coordIndex = 0
    var prevGeomIndex = 0;
    var geometryIndex = 0;
    var subtractCoordIndex = 0;
    
    (0..<poly.coordinates.count).forEach { j in
      (0..<poly.coordinates[j].count - 1).forEach { k in
        if (geometryIndex > prevGeomIndex) {
          prevGeomIndex = geometryIndex;
          subtractCoordIndex = coordIndex;
          tempOutput.append([]);
        }
        
        let currentCoord = poly.coordinates[j][k]
        let realCoordIndex = coordIndex - subtractCoordIndex;
        let p1 = poly.coordinates[geometryIndex][realCoordIndex + 1];
        let p0x = currentCoord.latitude;
        let p0y = currentCoord.longitude;
        let p1x = p1.latitude;
        let p1y = p1.longitude;
        tempOutput[geometryIndex].append(GeoJSON.Position(
          latitude: 0.75 * p0x + 0.25 * p1x,
          longitude: 0.75 * p0y + 0.25 * p1y
        ));
        tempOutput[geometryIndex].append(GeoJSON.Position(
          latitude: 0.25 * p0x + 0.75 * p1x,
          longitude: 0.25 * p0y + 0.75 * p1y
        ));
        
        coordIndex += 1
      }
      
      geometryIndex += 1
    }
    
    tempOutput.enumerated().forEach({ i, ring in
      tempOutput[i] = ring + [ring[0]]
    })
  }
}
