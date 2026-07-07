import Foundation
import RealityKit

/// Common interface for the live/replay hand renderers.
@MainActor
protocol HandVisualizing: AnyObject {
    func entity() -> Entity
    func clear()
    func update(hands: [String: [String: simd_float4x4]], relativeTo parent: Entity?)
}

extension HandSkeletonVisualizer: HandVisualizing {}
extension HandMeshVisualizer: HandVisualizing {}
