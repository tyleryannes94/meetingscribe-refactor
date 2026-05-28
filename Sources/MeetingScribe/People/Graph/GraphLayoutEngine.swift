import Foundation
import CoreGraphics

/// Simplified Fruchterman–Reingold force-directed layout (Phase 7). No
/// third-party graph library — just spring physics:
///   • every pair of nodes repels: `F_repulse = k² / distance`
///   • connected nodes attract along the edge: `F_attract = distance² / k`
///   • `k = sqrt(area / nodeCount)` is the ideal edge length
/// Runs with cooling (a temperature that caps per-step displacement and decays
/// each iteration) so the graph settles instead of oscillating. Pinned nodes
/// are skipped — the user has fixed them.
struct GraphLayout {
    /// Iteration count (spec calls for 100–200).
    var iterations: Int = 150
    /// Cooling factor applied to the temperature each iteration.
    var cooling: Double = 0.96
    /// Padding kept between nodes and the canvas edge.
    var padding: CGFloat = 48

    /// Lays out `nodes` in place. Edges reference nodes by `Person.id`.
    func layout(nodes: inout [PersonNode], edges: [RelationshipEdge], in bounds: CGRect) {
        let n = nodes.count
        guard n > 1 else {
            if n == 1 { nodes[0].position = CGPoint(x: bounds.midX, y: bounds.midY) }
            return
        }

        let area = Double(max(1, bounds.width) * max(1, bounds.height))
        let k = sqrt(area / Double(n))
        let k2 = k * k

        // id → index for edge endpoint lookup.
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(n)
        for (i, node) in nodes.enumerated() { indexByID[node.id] = i }

        var temperature = Double(bounds.width) / 8.0
        var disp = [CGVector](repeating: .zero, count: n)

        for _ in 0..<iterations {
            for i in 0..<n { disp[i] = .zero }

            // Repulsive forces between every pair.
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = Double(nodes[i].position.x - nodes[j].position.x)
                    let dy = Double(nodes[i].position.y - nodes[j].position.y)
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.01 { dist = 0.01 }
                    let force = k2 / dist
                    let ux = dx / dist, uy = dy / dist
                    disp[i].dx += ux * force; disp[i].dy += uy * force
                    disp[j].dx -= ux * force; disp[j].dy -= uy * force
                }
            }

            // Attractive forces along edges (stronger edges pull a bit harder).
            for edge in edges {
                guard let a = indexByID[edge.sourceID], let b = indexByID[edge.targetID] else { continue }
                let dx = Double(nodes[a].position.x - nodes[b].position.x)
                let dy = Double(nodes[a].position.y - nodes[b].position.y)
                var dist = (dx * dx + dy * dy).squareRoot()
                if dist < 0.01 { dist = 0.01 }
                let force = (dist * dist) / k * (1.0 + edge.weight)
                let ux = dx / dist, uy = dy / dist
                disp[a].dx -= ux * force; disp[a].dy -= uy * force
                disp[b].dx += ux * force; disp[b].dy += uy * force
            }

            // Apply displacement, capped by the current temperature; clamp to bounds.
            for i in 0..<n where !nodes[i].isPinned {
                let len = (disp[i].dx * disp[i].dx + disp[i].dy * disp[i].dy).squareRoot()
                guard len > 0.0001 else { continue }
                let capped = Swift.min(len, temperature)
                var x = Double(nodes[i].position.x) + disp[i].dx / len * capped
                var y = Double(nodes[i].position.y) + disp[i].dy / len * capped
                x = Swift.min(Double(bounds.maxX - padding), Swift.max(Double(bounds.minX + padding), x))
                y = Swift.min(Double(bounds.maxY - padding), Swift.max(Double(bounds.minY + padding), y))
                nodes[i].position = CGPoint(x: x, y: y)
            }

            temperature *= cooling
        }
    }
}
