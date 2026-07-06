import Foundation
import simd

struct HandArmatureState {
    private var lastHandAnchorFromJoint: [String: simd_float4x4] = [:]

    mutating func resolvedJoints(from observedHandAnchorFromJoint: [String: simd_float4x4]) -> [String: simd_float4x4] {
        var resolved = observedHandAnchorFromJoint
        let previous = lastHandAnchorFromJoint

        for jointName in HandJointCatalog.jointNames where resolved[jointName] == nil {
            if let parentName = HandJointCatalog.parentName(of: jointName),
               let parentMatrix = resolved[parentName],
               let previousParentMatrix = previous[parentName],
               let previousJointMatrix = previous[jointName] {
                let parentFromJoint = simd_inverse(previousParentMatrix) * previousJointMatrix
                resolved[jointName] = parentMatrix * parentFromJoint
            } else if let previousJointMatrix = previous[jointName] {
                resolved[jointName] = previousJointMatrix
            }
        }

        lastHandAnchorFromJoint = resolved
        return resolved
    }

    mutating func reset() {
        lastHandAnchorFromJoint.removeAll()
    }
}
