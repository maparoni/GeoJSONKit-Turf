import Foundation
#if !os(Linux)
import CoreLocation
#endif
import GeoJSONKit

extension GeoJSON.BoundingBox {
  
  public func contains(_ coordinate: GeoJSON.Position, ignoreBoundary: Bool = true) -> Bool {
    if ignoreBoundary {
      return southWesterlyLatitude < coordinate.latitude
          && northEasterlyLatitude > coordinate.latitude
          && southWesterlyLongitude < coordinate.longitude
          && northEasterlyLongitude > coordinate.longitude
    } else {
      return southWesterlyLatitude <= coordinate.latitude
          && northEasterlyLatitude >= coordinate.latitude
          && southWesterlyLongitude <= coordinate.longitude
          && northEasterlyLongitude >= coordinate.longitude
    }
  }

}