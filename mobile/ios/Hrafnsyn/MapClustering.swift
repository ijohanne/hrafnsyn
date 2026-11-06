import CoreGraphics

enum MapClustering {
    /// Returns disjoint groups whose weighted centroids have distinct tap targets.
    /// Merging is deterministic for the stable ordering supplied by the track list.
    static func groups(_ points: [CGPoint], clearance: CGFloat, anchoredIndex: Int? = nil) -> [[Int]] {
        struct Group {
            var indices: [Int]
            var center: CGPoint
        }
        var groups = points.enumerated().map { Group(indices: [$0.offset], center: $0.element) }
        var merged = true
        while merged {
            merged = false
            outer: for first in groups.indices {
                for second in (first + 1)..<groups.count {
                    let a = groups[first], b = groups[second]
                    if hypot(a.center.x - b.center.x, a.center.y - b.center.y) < clearance {
                        let count = CGFloat(a.indices.count + b.indices.count)
                        let indices = a.indices + b.indices
                        let centroid = CGPoint(
                            x: (a.center.x * CGFloat(a.indices.count) + b.center.x * CGFloat(b.indices.count)) / count,
                            y: (a.center.y * CGFloat(a.indices.count) + b.center.y * CGFloat(b.indices.count)) / count)
                        let anchor = anchoredIndex.flatMap { indices.contains($0) ? points[$0] : nil }
                        groups[first] = Group(indices: indices, center: anchor ?? centroid)
                        groups.remove(at: second)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return groups.map(\.indices)
    }
}
