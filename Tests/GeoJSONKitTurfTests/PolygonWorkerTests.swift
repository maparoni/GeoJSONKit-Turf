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
    await worker.simplify(geoJSON)
    XCTAssertTrue(worker.isLoaded)
  }
}

class GeoJSONSimplifier {
  private let polygonLock = NSLock()
  private var polygons: [GeoJSON.Feature] = []
  var isLoaded: Bool = false
  
  private let workerQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "app.maparoni.GeoJSONKitTurf.Simplifier"
    queue.qualityOfService = .utility
#if !os(Linux)
    queue.maxConcurrentOperationCount = ProcessInfo().activeProcessorCount
#endif
    return queue
  }()
  
  init() { }
  
  func simplify(_ geoJSON: GeoJSON) async {
    guard case .featureCollection(let features) = geoJSON.object else { return }

    let polygonFeatures = features
      .compactMap { feature -> GeoJSON.Feature? in
        let polygons = feature.polygons
        guard !polygons.isEmpty else { return nil }
        var updated = feature
        updated.polygons = polygons // this gets rid off geometry collections
        return updated
      }
    
    self.polygons = []
    return await withCheckedContinuation { continuation in
      workerQueue.addBarrierBlock {
        self.workerQueue.progress.completedUnitCount = 0
        self.workerQueue.progress.totalUnitCount = Int64(polygonFeatures.count)
        guard !polygonFeatures.isEmpty else {
          self.isLoaded = true
          return
        }
        
        polygonFeatures.forEach { feature in
          self.workerQueue.addOperation {
            var updated = feature
            updated.polygons = feature.polygons.map { $0.simplified(options: .init(algorithm: .RamerDouglasPeucker(tolerance: 0.001), highestQuality: false)) }
            self.polygonLock.lock(); defer { self.polygonLock.unlock() }
            self.polygons.append(updated)
          }
        }
        
        self.workerQueue.addBarrierBlock {
          self.isLoaded = true
          continuation.resume(returning: ())
        }
      }
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
