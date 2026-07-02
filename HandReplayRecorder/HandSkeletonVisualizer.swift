import Foundation
import RealityKit
import SwiftUI

@MainActor
final class HandSkeletonVisualizer {
    private let root = Entity()
    private let coordinateRoot: Entity?
    private let jointMaterial: SimpleMaterial
    private let boneMaterial: SimpleMaterial
    private var jointEntities: [String: ModelEntity] = [:]
    private var boneEntities: [String: ModelEntity] = [:]

    init(name: String, coordinateRoot: Entity? = nil, color: UIColor) {
        root.name = name
        self.coordinateRoot = coordinateRoot
        jointMaterial = SimpleMaterial(color: color, isMetallic: false)
        boneMaterial = SimpleMaterial(color: color.withAlphaComponent(0.55), isMetallic: false)
    }

    func entity() -> Entity {
        root
    }

    func clear() {
        root.isEnabled = false
        for entity in jointEntities.values {
            entity.isEnabled = false
        }
        for entity in boneEntities.values {
            entity.isEnabled = false
        }
    }

    func update(hands: [String: [String: simd_float4x4]], relativeTo parent: Entity? = nil) {
        root.isEnabled = true
        let activeJointKeys = Set(hands.flatMap { hand, joints in joints.keys.map { "\(hand)-\($0)" } })
        var activeBoneKeys = Set<String>()

        for (hand, joints) in hands {
            for (jointName, matrix) in joints {
                let key = "\(hand)-\(jointName)"
                let joint = jointEntity(for: key)
                joint.isEnabled = true
                joint.setTransformMatrix(matrix, relativeTo: parent ?? coordinateRoot)
            }

            for (start, end) in HandJointCatalog.bonePairs {
                guard let startMatrix = joints[start],
                      let endMatrix = joints[end]
                else { continue }
                let key = "\(hand)-\(start)-\(end)"
                activeBoneKeys.insert(key)
                let bone = boneEntity(for: key)
                updateBone(bone, start: position(from: startMatrix), end: position(from: endMatrix), relativeTo: parent ?? coordinateRoot)
                bone.isEnabled = true
            }
        }

        for (key, entity) in jointEntities where !activeJointKeys.contains(key) {
            entity.isEnabled = false
        }
        for (key, entity) in boneEntities where !activeBoneKeys.contains(key) {
            entity.isEnabled = false
        }
    }

    private func jointEntity(for key: String) -> ModelEntity {
        if let entity = jointEntities[key] {
            return entity
        }

        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.009),
            materials: [jointMaterial]
        )
        entity.name = "Joint-\(key)"
        root.addChild(entity)
        jointEntities[key] = entity
        return entity
    }

    private func boneEntity(for key: String) -> ModelEntity {
        if let entity = boneEntities[key] {
            return entity
        }

        let entity = ModelEntity(
            mesh: .generateBox(size: 1),
            materials: [boneMaterial]
        )
        entity.name = "Bone-\(key)"
        root.addChild(entity)
        boneEntities[key] = entity
        return entity
    }

    private func updateBone(_ entity: ModelEntity, start: SIMD3<Float>, end: SIMD3<Float>, relativeTo parent: Entity?) {
        let delta = end - start
        let length = simd_length(delta)
        guard length.isFinite, length > 0.001 else {
            entity.isEnabled = false
            return
        }

        entity.position = (start + end) * 0.5
        entity.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(delta))
        entity.scale = SIMD3<Float>(0.006, 0.006, length)
        if let parent {
            entity.setPosition((start + end) * 0.5, relativeTo: parent)
            entity.setOrientation(simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(delta)), relativeTo: parent)
        }
    }
}
