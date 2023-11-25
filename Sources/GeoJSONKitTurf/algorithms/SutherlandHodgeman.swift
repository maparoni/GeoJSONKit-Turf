//
//  SutherlandHodgeman.swift
//
//
//  Created by Adrian Schönig on 25/11/2023.
//

import Foundation

import GeoJSONKit

// Sutherland-Hodgeman polygon clipping algorithm
enum SutherlandHodgeman {
  
  static func clip(_ positions: [GeoJSON.Position], to boundingBox: GeoJSON.BoundingBox, close: Bool) -> [GeoJSON.Position] {
    var result = [GeoJSON.Position]()
    var prev: GeoJSON.Position
    var prevInside: Bool
    var inside: Bool
    var points = positions
    
    for edge in [1, 2, 4, 8] {
      result = []
      prev = close ? points.last! : points.first!
      prevInside = !(Self.bitCode(p: prev, bbox: boundingBox) & edge != 0)
      
      for point in points {
        inside = !(Self.bitCode(p: point, bbox: boundingBox) & edge != 0)
        
        if inside != prevInside {
          if let intersection = Self.intersect(a: prev, b: point, edge: edge, bbox: boundingBox) {
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
    return result
  }
  
  private static func intersect(a: GeoJSON.Position, b: GeoJSON.Position, edge: Int, bbox: GeoJSON.BoundingBox) -> GeoJSON.Position? {
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
  
  private static func bitCode(p: GeoJSON.Position, bbox: GeoJSON.BoundingBox) -> Int {
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
