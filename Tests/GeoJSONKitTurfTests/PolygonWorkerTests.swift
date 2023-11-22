import XCTest

import GeoJSONKit
@testable import GeoJSONKitTurf

class PolygonWorkerTests: XCTestCase {
  
  func testSimplifyLarge() throws {
    let data = try Fixture.loadData(folder: "simplify/in", filename: "countries-coastline-1km", extension: "geojson")
    let geoJSON = try GeoJSON(data: data)
    let simplified = geoJSON.simplified(options: .init(algorithm: .RamerDouglasPeucker(tolerance: 0.001)))
    XCTAssertNotNil(simplified)
  }
  
  func testSimplifyViaWorker() async throws {
    let data = try Fixture.loadData(folder: "simplify/in", filename: "countries-coastline-1km", extension: "geojson")
    let geoJSON = try GeoJSON(data: data)
    let worker = GeoJSONSimplifier()
    let simplified = await worker.simplify(geoJSON)
    XCTAssertEqual(simplified.count, 248)
  }
}

class GeoJSONSimplifier {
  init() { }
  
  func simplify(_ geoJSON: GeoJSON) async -> [GeoJSON.Feature] {
    guard case .featureCollection(let features) = geoJSON.object else { return [] }

    let polygonFeatures = features
      .compactMap { feature -> GeoJSON.Feature? in
        let polygons = feature.polygons
        guard !polygons.isEmpty else { return nil }
        var updated = feature
        updated.polygons = polygons // this gets rid off geometry collections
        return updated
      }
    guard !polygonFeatures.isEmpty else { return [] }
    
    return await withTaskGroup(of: GeoJSON.Feature.self) { group in
      for feature in polygonFeatures {
        group.addTask {
          await Task(priority: .utility) {
            var updated = feature
            updated.polygons = feature.polygons.map { $0.simplified(options: .init(algorithm: .RamerDouglasPeucker(tolerance: 0.001), highestQuality: false)) }
            return updated
          }.value
        }
      }
      
      return await group.reduce(into: []) { $0.append($1) }
    }
  }
}

extension GeoJSON.Feature {
  fileprivate var polygons: [GeoJSON.Polygon] {
    get {
      return geometry.geometries.compactMap { geometry -> GeoJSON.Polygon? in
        switch geometry {
        case .polygon(let polygon): return polygon
        default: return nil
        }
      }
    }
    set {
      if newValue.count == 0 {
        // do nothing
      } else if newValue.count == 1, let first = newValue.first {
        geometry = .single(.polygon(first))
      } else {
        geometry = .multi(newValue.map { .polygon($0) } )
      }
    }
  }
}
