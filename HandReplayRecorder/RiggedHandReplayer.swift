import Foundation
import RealityKit
import RealityKitContent
import simd

@MainActor
final class RiggedHandReplayer {
    private let root = Entity()
    private var skinnedModel: ModelEntity?
    private var resolvedMappings: [(index: Int, mapping: RiggedHandJointMapping.BoneMapping)] = []
    private var restJointTransforms = JointTransforms()
    private var isReady = false

    /// Converts ARKit meters into the authored Blender-hand skeleton units.
    private let modelScale: Float = 0.032

    private var jointTranslationScale: Float {
        1 / modelScale
    }

    init(name: String = "RiggedHandReplay") {
        root.name = name
        root.isEnabled = false
    }

    func entity() -> Entity {
        root
    }

    func load() async {
        guard skinnedModel == nil else { return }

        do {
            let model = try await Entity(named: "RiggedHand", in: realityKitContentBundle)
            model.name = "RiggedHandModel"
            model.scale = SIMD3<Float>(repeating: modelScale)
            root.addChild(model)

            guard let skinned = findSkinnedModelEntity(in: model) else {
                return
            }

            skinnedModel = skinned
            guard resolveMappings(on: skinned) else {
                skinnedModel = nil
                return
            }

            isReady = true
        } catch {
            isReady = false
        }
    }

    func clear() {
        root.isEnabled = false
    }

    func update(joints: [String: simd_float4x4], relativeTo parent: Entity?) {
        guard isReady,
              let skinnedModel,
              var poses = skinnedModel.components[SkeletalPosesComponent.self],
              var pose = poses.poses.default
        else {
            return
        }

        guard let wristMatrix = joints["wrist"] else {
            root.isEnabled = false
            return
        }

        root.isEnabled = true
        root.setTransformMatrix(wristMatrix, relativeTo: parent)

        var jointTransforms = pose.jointTransforms
        guard jointTransforms.count == restJointTransforms.count else { return }

        for entry in resolvedMappings {
            guard entry.index < jointTransforms.count else { continue }
            let mapping = entry.mapping

            switch mapping.driveMode {
            case .wristRoot:
                jointTransforms[entry.index] = Transform.identity
            case .metacarpal, .finger:
                guard let localMatrix = arkitLocalTransform(
                    joint: mapping.arkitJoint,
                    parent: mapping.arkitParent,
                    joints: joints
                ) else {
                    continue
                }

                let rest = restJointTransforms[entry.index]
                switch mapping.driveMode {
                case .metacarpal:
                    jointTransforms[entry.index] = metacarpalTransform(from: localMatrix, rest: rest)
                case .finger:
                    jointTransforms[entry.index] = fingerTransform(from: localMatrix, rest: rest)
                case .wristRoot:
                    break
                }
            }
        }

        pose.jointTransforms = jointTransforms
        poses.poses.default = pose
        skinnedModel.components.set(poses)
    }

    private func findSkinnedModelEntity(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity,
           model.components.has(SkeletalPosesComponent.self) {
            return model
        }

        for child in entity.children {
            if let match = findSkinnedModelEntity(in: child) {
                return match
            }
        }

        return nil
    }

    private func resolveMappings(on model: ModelEntity) -> Bool {
        guard let pose = model.components[SkeletalPosesComponent.self]?.poses.default else {
            return false
        }

        restJointTransforms = pose.jointTransforms
        resolvedMappings.removeAll()

        for mapping in RiggedHandJointMapping.boneMappings {
            guard let index = RiggedHandJointMapping.jointIndex(
                in: pose.jointNames,
                matching: mapping.rigJointSuffix
            ) else {
                continue
            }

            resolvedMappings.append((index, mapping))
        }

        return !resolvedMappings.isEmpty
    }

    private func arkitLocalTransform(
        joint: String,
        parent: String?,
        joints: [String: simd_float4x4]
    ) -> simd_float4x4? {
        guard let jointMatrix = joints[joint] else { return nil }
        guard let parent, let parentMatrix = joints[parent] else { return jointMatrix }
        return simd_inverse(parentMatrix) * jointMatrix
    }

    private func metacarpalTransform(from matrix: simd_float4x4, rest: Transform) -> Transform {
        var result = rest
        let arkitTranslation = position(from: matrix) * jointTranslationScale
        let restLength = simd_length(rest.translation)
        let arkitLength = simd_length(arkitTranslation)
        if restLength > 1e-5, arkitLength > 1e-5 {
            result.translation = rest.translation * (arkitLength / restLength)
        } else {
            result.translation = arkitTranslation
        }
        return result
    }

    private func fingerTransform(from matrix: simd_float4x4, rest: Transform) -> Transform {
        var result = rest
        result.translation = position(from: matrix) * jointTranslationScale
        result.rotation = simd_quatf(matrix)
        return result
    }
}
