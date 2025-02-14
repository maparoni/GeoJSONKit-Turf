//
//  GeoJSON+LineString+DecodePolylineString.swift
//
//  Created by Adrian Schoenig on 18/2/17.
//
//
import Foundation

import GeoJSONKit

extension GeoJSON.LineString {
  public init(encodedPolyline: String) {
    let bytes = encodedPolyline.utf8CString
    let length = bytes.count - 1 // ignore 0 at end
    var idx = 0
    
    var array: [GeoJSON.Position] = []
    
    var latitude = 0.0
    var longitude = 0.0
    while idx < length {
      var byte = 0
      var res = 0
      var shift = 0
      
      repeat {
        if idx > length {
          break
        }
        byte = Int(bytes[idx]) - 63
        idx += 1
        res |= (byte & 0x1F) << shift
        shift += 5
      } while byte >= 0x20
      
      let deltaLat = ((res & 1) != 0 ? ~(res >> 1) : (res >> 1));
      latitude += Double(deltaLat)
      
      shift = 0
      res = 0
      
      repeat {
        if idx > length {
          break
        }
        byte = Int(bytes[idx]) - 0x3F
        idx += 1
        res |= (byte & 0x1F) << shift
        shift += 5
      } while byte >= 0x20
      
      let deltaLon = ((res & 1) != 0 ? ~(res >> 1) : (res >> 1));
      longitude += Double(deltaLon)
      
      let finalLat = latitude * 1E-5
      let finalLon = longitude * 1E-5
      let coordinate = GeoJSON.Position(latitude: finalLat, longitude: finalLon)
      array.append(coordinate)
    }
    
    self.init(positions: array)
  }
}
