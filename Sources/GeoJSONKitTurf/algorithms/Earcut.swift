//
//  Earcut.swift
//  GeoJSONKitTurf
//
//  Ported from https://github.com/mapbox/earcut (v3.0.1), which turf.js's `tesselate` uses.
//
//  ISC License
//
//  Copyright (c) 2016, Mapbox
//
//  Permission to use, copy, modify, and/or distribute this software for any purpose
//  with or without fee is hereby granted, provided that the above copyright notice
//  and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND ISC DISCLAIMS ALL WARRANTIES WITH REGARD TO
//  THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS.
//  IN NO EVENT SHALL ISC BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
//  CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA
//  OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
//  ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

/// Ear clipping, with each hole bridged to the outside first, and the corners sorted along a
/// z-order curve, so that checking an ear only looks at the corners near it.
///
/// The corners are kept as linked lists in arrays, with -1 for none, as a node per corner
/// otherwise costs an allocation each.
struct Earcut {
  private var xs: [Double] = []
  private var ys: [Double] = []
  /// Where the node's corner is in the input, which bridges repeat.
  private var source: [Int] = []
  private var previous: [Int] = []
  private var next: [Int] = []
  private var z: [Int] = []
  private var previousZ: [Int] = []
  private var nextZ: [Int] = []
  private var steiner: [Bool] = []
  private var triangles: [Int] = []

  private var minX = 0.0
  private var minY = 0.0
  private var invSize = 0.0

  /// - Parameters:
  ///   - x: All the rings' x coordinates, the exterior's first.
  ///   - y: The same for y.
  ///   - holeStarts: Where each hole starts in `x` and `y`.
  /// - Returns: Each three are a triangle's corners, as indexes into `x` and `y`, mostly
  ///   counter-clockwise.
  static func triangulate(x: [Double], y: [Double], holeStarts: [Int]) -> [Int] {
    precondition(x.count == y.count)
    var earcut = Earcut()
    earcut.reserve(x.count)
    let outerEnd = holeStarts.first ?? x.count
    var outer = earcut.linkedList(x, y, 0, outerEnd, counterClockwise: true)
    guard outer >= 0, earcut.next[outer] != earcut.previous[outer] else { return [] }
    if !holeStarts.isEmpty {
      outer = earcut.eliminateHoles(x, y, holeStarts: holeStarts, outer: outer)
    }
    earcut.untangle(outer)

    // Only worth it for a shape that isn't too simple.
    if x.count > 80 {
      // Unlike the original, the box covers the holes too, so that one outside the exterior
      // can't end up with z-order values out of range.
      var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
      for index in x.indices {
        minX = min(minX, x[index])
        minY = min(minY, y[index])
        maxX = max(maxX, x[index])
        maxY = max(maxY, y[index])
      }
      let size = max(maxX - minX, maxY - minY)
      if size > 0, size.isFinite {
        earcut.minX = minX
        earcut.minY = minY
        earcut.invSize = 32767 / size
      }
    }

    earcut.earcutLinked(outer, pass: 0)
    return earcut.triangles
  }

  private mutating func reserve(_ count: Int) {
    // Each hole's bridge adds two.
    let nodes = count + count / 8 + 16
    xs.reserveCapacity(nodes)
    ys.reserveCapacity(nodes)
    source.reserveCapacity(nodes)
    previous.reserveCapacity(nodes)
    next.reserveCapacity(nodes)
    z.reserveCapacity(nodes)
    previousZ.reserveCapacity(nodes)
    nextZ.reserveCapacity(nodes)
    steiner.reserveCapacity(nodes)
    triangles.reserveCapacity(count * 3)
  }

  // MARK: - Rings

  /// A circular linked list of the corners from `start` up to `end`, going around the given way.
  private mutating func linkedList(_ x: [Double], _ y: [Double], _ start: Int, _ end: Int, counterClockwise: Bool) -> Int {
    guard start < end else { return -1 }
    var last = -1
    if counterClockwise == (Self.signedArea(x, y, start, end) > 0) {
      for index in start..<end {
        last = insertNode(index, x[index], y[index], after: last)
      }
    } else {
      for index in (start..<end).reversed() {
        last = insertNode(index, x[index], y[index], after: last)
      }
    }
    if last >= 0, equals(last, next[last]) {
      removeNode(last)
      last = next[last]
    }
    return last
  }

  /// Twice the area, positive for counter-clockwise.
  private static func signedArea(_ x: [Double], _ y: [Double], _ start: Int, _ end: Int) -> Double {
    var sum = 0.0
    var previous = end - 1
    for index in start..<end {
      sum += (x[previous] - x[index]) * (y[index] + y[previous])
      previous = index
    }
    return sum
  }

  /// Removes corners that are the same as the next one or in line with their neighbours.
  private mutating func filterPoints(_ start: Int, _ end: Int = -1) -> Int {
    guard start >= 0 else { return start }
    var end = end < 0 ? start : end
    var p = start
    var again: Bool
    repeat {
      again = false
      if !steiner[p], equals(p, next[p]) || area(previous[p], p, next[p]) == 0 {
        removeNode(p)
        p = previous[p]
        end = p
        if p == next[p] { break }
        again = true
      } else {
        p = next[p]
      }
    } while again || p != end
    return end
  }

  // MARK: - Ears

  /// The main loop, which slices off ears one by one.
  private mutating func earcutLinked(_ start: Int, pass: Int) {
    guard start >= 0 else { return }
    var ear = start
    if pass == 0, invSize != 0 { indexCurve(ear) }

    var stop = ear
    while previous[ear] != next[ear] {
      let before = previous[ear], after = next[ear]
      if invSize != 0 ? isEarHashed(ear) : isEar(ear) {
        triangles.append(source[before])
        triangles.append(source[ear])
        triangles.append(source[after])
        removeNode(ear)
        // Skipping the next corner leaves fewer slivers.
        ear = next[after]
        stop = next[after]
        continue
      }
      ear = after

      // Around the whole of what's left, and no more ears.
      if ear == stop {
        switch pass {
        case 0:
          // Without corners in line, and again.
          earcutLinked(filterPoints(ear), pass: 1)
        case 1:
          // Curing small places where it crosses itself.
          earcutLinked(cureLocalIntersections(filterPoints(ear)), pass: 2)
        default:
          // As a last resort, splitting it in two.
          splitEarcut(ear)
        }
        break
      }
    }
  }

  private func isEar(_ ear: Int) -> Bool {
    let a = previous[ear], b = ear, c = next[ear]
    // Reflex, so it can't be an ear.
    guard area(a, b, c) < 0 else { return false }
    let ax = xs[a], bx = xs[b], cx = xs[c], ay = ys[a], by = ys[b], cy = ys[c]
    let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
    var p = next[c]
    while p != a {
      if xs[p] >= x0, xs[p] <= x1, ys[p] >= y0, ys[p] <= y1,
         Self.pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, xs[p], ys[p]),
         area(previous[p], p, next[p]) >= 0 {
        return false
      }
      p = next[p]
    }
    return true
  }

  private func isEarHashed(_ ear: Int) -> Bool {
    let a = previous[ear], b = ear, c = next[ear]
    guard area(a, b, c) < 0 else { return false }
    let ax = xs[a], bx = xs[b], cx = xs[c], ay = ys[a], by = ys[b], cy = ys[c]
    let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
    let minZ = zOrder(x0, y0), maxZ = zOrder(x1, y1)

    func blocks(_ p: Int) -> Bool {
      xs[p] >= x0 && xs[p] <= x1 && ys[p] >= y0 && ys[p] <= y1 && p != a && p != c
        && Self.pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, xs[p], ys[p])
        && area(previous[p], p, next[p]) >= 0
    }

    // Looking for corners inside the triangle in both directions along the curve.
    var p = previousZ[ear], n = nextZ[ear]
    while p >= 0, z[p] >= minZ, n >= 0, z[n] <= maxZ {
      if blocks(p) { return false }
      p = previousZ[p]
      if blocks(n) { return false }
      n = nextZ[n]
    }
    while p >= 0, z[p] >= minZ {
      if blocks(p) { return false }
      p = previousZ[p]
    }
    while n >= 0, z[n] <= maxZ {
      if blocks(n) { return false }
      n = nextZ[n]
    }
    return true
  }

  /// Slices off where two edges with one between them cross.
  private mutating func cureLocalIntersections(_ start: Int) -> Int {
    var start = start
    var p = start
    repeat {
      let a = previous[p], b = next[next[p]]
      if !equals(a, b), intersects(a, p, next[p], b), locallyInside(a, b), locallyInside(b, a) {
        triangles.append(source[a])
        triangles.append(source[p])
        triangles.append(source[b])
        removeNode(p)
        removeNode(next[p])
        p = b
        start = b
      }
      p = next[p]
    } while p != start
    return filterPoints(p)
  }

  /// Splits it in two along a diagonal that's inside it, and does each on its own.
  private mutating func splitEarcut(_ start: Int) {
    var a = start
    repeat {
      var b = next[next[a]]
      while b != previous[a] {
        if source[a] != source[b], isValidDiagonal(a, b) {
          var c = splitPolygon(a, b)
          let first = filterPoints(a, next[a])
          c = filterPoints(c, next[c])
          earcutLinked(first, pass: 0)
          earcutLinked(c, pass: 0)
          return
        }
        b = next[b]
      }
      a = next[a]
    } while a != start
  }

  // MARK: - Holes

  /// Links every hole into the outside, which leaves one ring.
  private mutating func eliminateHoles(_ x: [Double], _ y: [Double], holeStarts: [Int], outer: Int) -> Int {
    var queue: [Int] = []
    for (index, start) in holeStarts.enumerated() {
      let end = index + 1 < holeStarts.count ? holeStarts[index + 1] : x.count
      let list = linkedList(x, y, start, end, counterClockwise: false)
      guard list >= 0 else { continue }
      if list == next[list] { steiner[list] = true }
      queue.append(leftmost(list))
    }
    queue.sort { compareXY($0, $1) < 0 }

    // From left to right.
    var outer = outer
    for hole in queue {
      outer = eliminateHole(hole, outer)
    }
    return outer
  }

  private func compareXY(_ a: Int, _ b: Int) -> Double {
    var result = xs[a] - xs[b]
    // Where the leftmost corners of two holes meet, counter-clockwise, so that the bridge to
    // the outside is always the corner they meet at.
    if result == 0 {
      result = ys[a] - ys[b]
      if result == 0 {
        let aSlope = (ys[next[a]] - ys[a]) / (xs[next[a]] - xs[a])
        let bSlope = (ys[next[b]] - ys[b]) / (xs[next[b]] - xs[b])
        result = aSlope - bSlope
      }
    }
    return result
  }

  private mutating func eliminateHole(_ hole: Int, _ outer: Int) -> Int {
    guard let bridge = findHoleBridge(hole, outer) else { return outer }
    let bridgeReverse = splitPolygon(bridge, hole)
    _ = filterPoints(bridgeReverse, next[bridgeReverse])
    return filterPoints(bridge, next[bridge])
  }

  /// David Eberly's way of finding a corner of the outside that the hole can link to.
  private func findHoleBridge(_ hole: Int, _ outer: Int) -> Int? {
    var p = outer
    let hx = xs[hole], hy = ys[hole]
    var qx = -Double.infinity
    var m = -1
    // Not in the original: where the ray hits an edge from outside first, as it goes the
    // other way, the hole is outside, so there's nothing for it to cut out. Bridging it to
    // the edge after that would cut through the polygon instead.
    var outsideX = -Double.infinity

    // The edge that a ray to the left of the hole's leftmost corner hits first, and of that
    // the end that's further left, unless the ray hits a corner.
    if equals(hole, p) { return p }
    repeat {
      if equals(hole, next[p]) {
        return next[p]
      } else if hy <= ys[p], hy >= ys[next[p]], ys[next[p]] != ys[p] {
        let x = xs[p] + (hy - ys[p]) * (xs[next[p]] - xs[p]) / (ys[next[p]] - ys[p])
        if x <= hx, x > qx {
          qx = x
          m = xs[p] < xs[next[p]] ? p : next[p]
          // The hole touches the outside's edge.
          if x == hx { return m }
        }
      } else if hy >= ys[p], hy <= ys[next[p]], ys[next[p]] != ys[p] {
        let x = xs[p] + (hy - ys[p]) * (xs[next[p]] - xs[p]) / (ys[next[p]] - ys[p])
        if x <= hx { outsideX = max(outsideX, x) }
      }
      p = next[p]
    } while p != outer
    guard m >= 0, outsideX <= qx else { return nil }

    // Corners inside the triangle of the hole's corner, where the ray hits and that end
    // would be in the way, and of those the one at the smallest angle to the ray isn't.
    let stop = m
    let mx = xs[m], my = ys[m]
    var tanMin = Double.infinity
    p = m
    repeat {
      if hx >= xs[p], xs[p] >= mx, hx != xs[p],
         Self.pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, xs[p], ys[p]) {
        let tan = abs(hy - ys[p]) / (hx - xs[p])
        if locallyInside(p, hole),
           tan < tanMin || (tan == tanMin && (xs[p] > xs[m] || (xs[p] == xs[m] && sectorContainsSector(m, p)))) {
          m = p
          tanMin = tan
        }
      }
      p = next[p]
    } while p != stop
    return m
  }

  /// Whether the sector at `m` contains the one at `p`, where they're in the same place.
  private func sectorContainsSector(_ m: Int, _ p: Int) -> Bool {
    area(previous[m], m, previous[p]) < 0 && area(next[p], m, next[m]) < 0
  }

  private func leftmost(_ start: Int) -> Int {
    var p = start, leftmost = start
    repeat {
      if xs[p] < xs[leftmost] || (xs[p] == xs[leftmost] && ys[p] < ys[leftmost]) { leftmost = p }
      p = next[p]
    } while p != start
    return leftmost
  }

  // MARK: - Crossings

  /// Not in the original: detailed coastlines cross themselves and their holes in tiny
  /// loops, each of which goes the wrong way around, and with a few of those around what's
  /// left there are no ears, and the last resorts leave out much more than the loops.
  /// Reversing the stretch between two edges that cross swaps them for two that don't, and
  /// shorter ones, so it always ends.
  private mutating func untangle(_ start: Int) {
    var ring: [Int] = []
    var p = start
    repeat {
      ring.append(p)
      p = next[p]
    } while p != start
    guard ring.count >= 4 else { return }

    var grid = EdgeGrid(xs: ring.map { xs[$0] }, ys: ring.map { ys[$0] })
    var crossings: [(Int, Int)] = []
    for node in ring {
      let edge = grid.add(node, next[node], xs: xs, ys: ys)
      grid.forEachNear(edge) { other in
        if crosses(grid.ends[edge], grid.ends[other]) { crossings.append((edge, other)) }
      }
    }

    // Each fix makes two edges, which are all that can cross something new.
    var budget = ring.count * 4
    while let (first, second) = crossings.popLast(), budget > 0 {
      guard isEdge(grid.ends[first]), isEdge(grid.ends[second]) else { continue }
      budget -= 1
      let (a, b) = directed(grid.ends[first])
      let (c, d) = directed(grid.ends[second])
      reverseShorter(from: b, to: c, orFrom: d, to: a)
      for edge in [grid.add(a, c, xs: xs, ys: ys), grid.add(b, d, xs: xs, ys: ys)] {
        grid.forEachNear(edge) { other in
          if isEdge(grid.ends[other]), crosses(grid.ends[edge], grid.ends[other]) { crossings.append((edge, other)) }
        }
      }
    }

    // A figure of eight could've ended up going the other way around.
    var sum = 0.0
    p = start
    repeat {
      sum += (xs[p] - xs[next[p]]) * (ys[next[p]] + ys[p])
      p = next[p]
    } while p != start
    if sum < 0 {
      repeat {
        swap(&previous[p], &next[p])
        p = previous[p]
      } while p != start
    }
  }

  private func isEdge(_ ends: (Int, Int)) -> Bool {
    next[ends.0] == ends.1 || next[ends.1] == ends.0
  }

  /// The ends in the order the ring goes.
  private func directed(_ ends: (Int, Int)) -> (Int, Int) {
    next[ends.0] == ends.1 ? ends : (ends.1, ends.0)
  }

  /// Right across, as touching only happens where they share a corner, or along each other.
  private func crosses(_ first: (Int, Int), _ second: (Int, Int)) -> Bool {
    let (a, b) = first, (c, d) = second
    return area(a, b, c) * area(a, b, d) < 0 && area(c, d, a) * area(c, d, b) < 0
  }

  /// Either reverses one stretch or the other, which leaves the same ring the other way
  /// around, so only the shorter one, found by walking both at once.
  private mutating func reverseShorter(from b: Int, to c: Int, orFrom d: Int, to a: Int) {
    var first = [b], second = [d]
    while first.last != c, second.last != a {
      first.append(next[first.last!])
      second.append(next[second.last!])
    }
    let stretch = first.last == c ? first : second
    let before = previous[stretch[0]], after = next[stretch[stretch.count - 1]]
    for node in stretch {
      swap(&previous[node], &next[node])
    }
    let head = stretch[stretch.count - 1], tail = stretch[0]
    next[before] = head
    previous[head] = before
    next[tail] = after
    previous[after] = tail
  }

  // MARK: - Z-order

  /// Links the corners in z-order too.
  private mutating func indexCurve(_ start: Int) {
    var p = start
    repeat {
      if z[p] == 0 { z[p] = zOrder(xs[p], ys[p]) }
      previousZ[p] = previous[p]
      nextZ[p] = next[p]
      p = next[p]
    } while p != start
    nextZ[previousZ[p]] = -1
    previousZ[p] = -1
    sortLinked(p)
  }

  /// Simon Tatham's merge sort for linked lists.
  private mutating func sortLinked(_ start: Int) {
    var list = start
    var inSize = 1
    var merges: Int
    repeat {
      var p = list
      list = -1
      var tail = -1
      merges = 0
      while p >= 0 {
        merges += 1
        var q = p
        var pSize = 0
        for _ in 0..<inSize {
          pSize += 1
          q = nextZ[q]
          if q < 0 { break }
        }
        var qSize = inSize
        while pSize > 0 || (qSize > 0 && q >= 0) {
          let e: Int
          if pSize != 0, qSize == 0 || q < 0 || z[p] <= z[q] {
            e = p
            p = nextZ[p]
            pSize -= 1
          } else {
            e = q
            q = nextZ[q]
            qSize -= 1
          }
          if tail >= 0 { nextZ[tail] = e } else { list = e }
          previousZ[e] = tail
          tail = e
        }
        p = q
      }
      nextZ[tail] = -1
      inSize *= 2
    } while merges > 1
  }

  /// Where the point is along the curve, from its coordinates as 15-bit integers within the
  /// bounding box.
  private func zOrder(_ x: Double, _ y: Double) -> Int {
    func integer(_ value: Double) -> Int {
      // Written so that NaN ends up at 0 too.
      value > 0 ? (value < 32767 ? Int(value) : 32767) : 0
    }
    func spread(_ value: Int) -> Int {
      var value = value
      value = (value | (value << 8)) & 0x00FF00FF
      value = (value | (value << 4)) & 0x0F0F0F0F
      value = (value | (value << 2)) & 0x33333333
      value = (value | (value << 1)) & 0x55555555
      return value
    }
    return spread(integer((x - minX) * invSize)) | (spread(integer((y - minY) * invSize)) << 1)
  }

  // MARK: - Geometry

  private static func pointInTriangle(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ px: Double, _ py: Double) -> Bool {
    (cx - px) * (ay - py) >= (ax - px) * (cy - py)
      && (ax - px) * (by - py) >= (bx - px) * (ay - py)
      && (bx - px) * (cy - py) >= (cx - px) * (by - py)
  }

  private static func pointInTriangleExceptFirst(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ px: Double, _ py: Double) -> Bool {
    !(ax == px && ay == py) && pointInTriangle(ax, ay, bx, by, cx, cy, px, py)
  }

  /// Whether a diagonal between the two is inside the polygon.
  private func isValidDiagonal(_ a: Int, _ b: Int) -> Bool {
    guard source[next[a]] != source[b], source[previous[a]] != source[b], !intersectsPolygon(a, b) else { return false }
    // Locally visible, without making sectors that face each other.
    if locallyInside(a, b), locallyInside(b, a), middleInside(a, b),
       area(previous[a], a, previous[b]) != 0 || area(a, previous[b], b) != 0 {
      return true
    }
    // The special case of no length.
    return equals(a, b) && area(previous[a], a, next[a]) > 0 && area(previous[b], b, next[b]) > 0
  }

  /// Negative for counter-clockwise.
  private func area(_ p: Int, _ q: Int, _ r: Int) -> Double {
    (ys[q] - ys[p]) * (xs[r] - xs[q]) - (xs[q] - xs[p]) * (ys[r] - ys[q])
  }

  private func equals(_ a: Int, _ b: Int) -> Bool {
    xs[a] == xs[b] && ys[a] == ys[b]
  }

  private func intersects(_ p1: Int, _ q1: Int, _ p2: Int, _ q2: Int) -> Bool {
    func sign(_ value: Double) -> Int { value > 0 ? 1 : value < 0 ? -1 : 0 }
    let o1 = sign(area(p1, q1, p2))
    let o2 = sign(area(p1, q1, q2))
    let o3 = sign(area(p2, q2, p1))
    let o4 = sign(area(p2, q2, q1))
    if o1 != o2, o3 != o4 { return true }
    // In line, with one end on the other edge.
    if o1 == 0, onSegment(p1, p2, q1) { return true }
    if o2 == 0, onSegment(p1, q2, q1) { return true }
    if o3 == 0, onSegment(p2, p1, q2) { return true }
    if o4 == 0, onSegment(p2, q1, q2) { return true }
    return false
  }

  /// For `p`, `q` and `r` in line, whether `q` is between the other two.
  private func onSegment(_ p: Int, _ q: Int, _ r: Int) -> Bool {
    xs[q] <= max(xs[p], xs[r]) && xs[q] >= min(xs[p], xs[r]) && ys[q] <= max(ys[p], ys[r]) && ys[q] >= min(ys[p], ys[r])
  }

  private func intersectsPolygon(_ a: Int, _ b: Int) -> Bool {
    var p = a
    repeat {
      if source[p] != source[a], source[next[p]] != source[a], source[p] != source[b], source[next[p]] != source[b],
         intersects(p, next[p], a, b) {
        return true
      }
      p = next[p]
    } while p != a
    return false
  }

  private func locallyInside(_ a: Int, _ b: Int) -> Bool {
    area(previous[a], a, next[a]) < 0
      ? area(a, b, next[a]) >= 0 && area(a, previous[a], b) >= 0
      : area(a, b, previous[a]) < 0 || area(a, next[a], b) < 0
  }

  private func middleInside(_ a: Int, _ b: Int) -> Bool {
    var p = a
    var inside = false
    let px = (xs[a] + xs[b]) / 2, py = (ys[a] + ys[b]) / 2
    repeat {
      let q = next[p]
      if (ys[p] > py) != (ys[q] > py), ys[q] != ys[p], px < (xs[q] - xs[p]) * (py - ys[p]) / (ys[q] - ys[p]) + xs[p] {
        inside.toggle()
      }
      p = q
    } while p != a
    return inside
  }

  // MARK: - Nodes

  /// Links the two with a bridge: in the same ring that splits it in two, and from a hole to
  /// the outside that makes them one.
  private mutating func splitPolygon(_ a: Int, _ b: Int) -> Int {
    let a2 = createNode(source[a], xs[a], ys[a])
    let b2 = createNode(source[b], xs[b], ys[b])
    let an = next[a], bp = previous[b]
    next[a] = b
    previous[b] = a
    next[a2] = an
    previous[an] = a2
    next[b2] = a2
    previous[a2] = b2
    next[bp] = b2
    previous[b2] = bp
    return b2
  }

  private mutating func insertNode(_ index: Int, _ x: Double, _ y: Double, after last: Int) -> Int {
    let p = createNode(index, x, y)
    if last < 0 {
      previous[p] = p
      next[p] = p
    } else {
      next[p] = next[last]
      previous[p] = last
      previous[next[last]] = p
      next[last] = p
    }
    return p
  }

  /// Leaves the node's own links as they were, which the callers rely on.
  private mutating func removeNode(_ p: Int) {
    previous[next[p]] = previous[p]
    next[previous[p]] = next[p]
    if previousZ[p] >= 0 { nextZ[previousZ[p]] = nextZ[p] }
    if nextZ[p] >= 0 { previousZ[nextZ[p]] = previousZ[p] }
  }

  private mutating func createNode(_ index: Int, _ x: Double, _ y: Double) -> Int {
    xs.append(x)
    ys.append(y)
    source.append(index)
    previous.append(-1)
    next.append(-1)
    z.append(0)
    previousZ.append(-1)
    nextZ.append(-1)
    steiner.append(false)
    return xs.count - 1
  }
}

/// Edges by where they are, so that looking for those that might cross one only looks
/// nearby. Edges stay in it once they're gone from the ring, so it's up to the caller to
/// skip those.
///
/// The cells are about the size of an edge, as detailed rings are dense along their length
/// but take up little of their bounding box. The few edges much longer than that, as where
/// a ring is straight for a while, are compared with everything instead.
private struct EdgeGrid {
  private(set) var ends: [(Int, Int)] = []
  private var spans: [(columns: ClosedRange<Int>, rows: ClosedRange<Int>)?] = []
  private var cells: [Int: [Int]] = [:]
  private var long: [Int] = []
  private let minX: Double, minY: Double, size: Double
  private let columns: Int

  private static let mostCells = 16

  /// - Parameter ring: Each corner's coordinates, in the order the ring goes.
  init(xs: [Double], ys: [Double]) {
    let count = xs.count
    var total = 0.0
    for index in 0..<count {
      let following = (index + 1) % count
      total += max(abs(xs[following] - xs[index]), abs(ys[following] - ys[index]))
    }
    let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
    let extent = max(maxX - minX, maxY - minY)
    // At least so that there aren't more than about a million columns.
    let size = max(2 * total / Double(max(count, 1)), extent / 1_000_000)
    self.size = size > 0 && size.isFinite ? size : 1
    self.minX = minX
    self.minY = minY
    columns = Self.index(maxX, from: minX, size: self.size) + 1
    ends.reserveCapacity(count + count / 4)
    spans.reserveCapacity(count + count / 4)
    cells.reserveCapacity(count)
  }

  private static func index(_ value: Double, from minimum: Double, size: Double) -> Int {
    let index = (value - minimum) / size
    // Written so that NaN ends up at 0 too.
    return index > 0 ? (index < 1_000_000 ? Int(index) : 1_000_000) : 0
  }

  mutating func add(_ a: Int, _ b: Int, xs: [Double], ys: [Double]) -> Int {
    let edge = ends.count
    ends.append((a, b))
    let columns = Self.index(min(xs[a], xs[b]), from: minX, size: size)...Self.index(max(xs[a], xs[b]), from: minX, size: size)
    let rows = Self.index(min(ys[a], ys[b]), from: minY, size: size)...Self.index(max(ys[a], ys[b]), from: minY, size: size)
    guard columns.count * rows.count <= Self.mostCells else {
      spans.append(nil)
      long.append(edge)
      return edge
    }
    spans.append((columns, rows))
    for row in rows {
      for column in columns {
        cells[row * self.columns + column, default: []].append(edge)
      }
    }
    return edge
  }

  /// The others that might cross it, some more than once.
  func forEachNear(_ edge: Int, _ body: (Int) -> Void) {
    guard let span = spans[edge] else {
      for other in ends.indices where other != edge { body(other) }
      return
    }
    for row in span.rows {
      for column in span.columns {
        for other in cells[row * columns + column] ?? [] where other != edge {
          body(other)
        }
      }
    }
    for other in long where other != edge { body(other) }
  }
}
