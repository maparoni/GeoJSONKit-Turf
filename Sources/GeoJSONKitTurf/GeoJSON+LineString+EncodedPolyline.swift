//
//  GeoJSON+LineString+EncodedPolyline.swift
//
//  Created by Adrian Schoenig on 18/2/17.
//
//
import Foundation

import GeoJSONKit

extension GeoJSON.LineString {
  
  // MARK: - Decode
  
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
  
  // MARK: - Encode
  
  /// Encodes this `GeoJSON.LineString` to a `String`
  ///
  /// Adopted from https://github.com/raphaelmor/Polyline/blob/master/Sources/Polyline/Polyline.swift
  ///
  /// - parameter precision: The precision used to encode coordinates (default: `1e5`)
  /// - returns: A `String` representing the encoded polyline
  public func encodedPolyline(precision: Double = 1e5) -> String {
    var previousCoordinate = IntegerCoordinates(0, 0)
    var encodedPolyline = ""
    
    for position in positions {
      let intLatitude  = Int(round(position.latitude * precision))
      let intLongitude = Int(round(position.longitude * precision))
      
      let coordinatesDifference = (intLatitude - previousCoordinate.latitude, intLongitude - previousCoordinate.longitude)
      encodedPolyline += Self.encodeCoordinate(coordinatesDifference)
      
      previousCoordinate = (intLatitude, intLongitude)
    }
    
    return encodedPolyline
  }
  
  private typealias IntegerCoordinates = (latitude: Int, longitude: Int)
  
  private static func encodeCoordinate(_ coordinate: IntegerCoordinates) -> String {
    let latitudeString  = encodeSingleComponent(coordinate.latitude)
    let longitudeString = encodeSingleComponent(coordinate.longitude)
    return latitudeString + longitudeString
  }

  private static func encodeSingleComponent(_ value: Int) -> String {
    var intValue = value
    if intValue < 0 {
      intValue = intValue << 1
      intValue = ~intValue
    } else {
      intValue = intValue << 1
    }
    return encodeFiveBitComponents(intValue)
  }

  private static func encodeLevel(_ level: UInt32) -> String {
    return encodeFiveBitComponents(Int(level))
  }

  private static func encodeFiveBitComponents(_ value: Int) -> String {
    var remainingComponents = value
    
    var fiveBitComponent = 0
    var returnString = String()
    
    repeat {
      fiveBitComponent = remainingComponents & 0x1F
      
      if remainingComponents >= 0x20 {
        fiveBitComponent |= 0x20
      }
      
      fiveBitComponent += 63
      
      let char = UnicodeScalar(fiveBitComponent)!
      returnString.append(String(char))
      remainingComponents = remainingComponents >> 5
    } while (remainingComponents != 0)
    
    return returnString
  }
}
