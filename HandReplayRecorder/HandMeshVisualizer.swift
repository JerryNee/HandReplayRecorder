import Foundation
import RealityKit
import SwiftUI

/// Renders hands as solid 3D geometry (palm slab + finger capsules) instead of
/// a debug skeleton. Driven purely by joint positions, so it works with the
/// translation-only matrices produced by replay interpolation.
@MainActor
final class HandMeshVisualizer {
    private let root = Entity()
    private let coordinateRoot: Entity?
    private let skinMaterial: PhysicallyBasedMaterial

    private var jointEntities: [String: ModelEntity] = [:]
    private var segmentEntities: [String: ModelEntity] = [:]
    private var palmEntities: [String: ModelEntity] = [:]

    private let unitSphere = MeshResource.generateSphere(radius: 1)
    private let unitCylinder = MeshResource.generateCylinder(height: 1, radius: 1)
    private let unitPalm = MeshResource.generateBox(width: 1, height: 1, depth: 1, cornerRadius: 0.18)

    /// Bone segments rendered as cylinders. Wrist-to-metacarpal and
    /// metacarpal-to-knuckle runs are covered by the palm slab, except the
    /// thumb base which sticks out past the palm edge.
    private static let fingerSegments: [(String, String)] = {
        var segments: [(String, String)] = [
            ("wrist", "thumbKnuckle"),
            ("thumbKnuckle", "thumbIntermediateBase"),
            ("thumbIntermediateBase", "thumbIntermediateTip"),
            ("thumbIntermediateTip", "thumbTip")
        ]
        for finger in ["indexFinger", "middleFinger", "ringFinger", "littleFinger"] {
            segments.append(("\(finger)Knuckle", "\(finger)IntermediateBase"))
            segments.append(("\(finger)IntermediateBase", "\(finger)IntermediateTip"))
            segments.append(("\(finger)IntermediateTip", "\(finger)Tip"))
        }
        return segments
    }()

    /// Joints that get a sphere to round off the cylinder ends.
    private static let sphereJoints: [String] = {
        var joints = ["thumbKnuckle", "thumbIntermediateBase", "thumbIntermediateTip", "thumbTip"]
        for finger in ["indexFinger", "middleFinger", "ringFinger", "littleFinger"] {
            joints.append("\(finger)Knuckle")
            joints.append("\(finger)IntermediateBase")
            joints.append("\(finger)IntermediateTip")
            joints.append("\(finger)Tip")
        }
        return joints
    }()

    init(
        name: String,
        coordinateRoot: Entity? = nil,
        color: UIColor = UIColor(red: 0.87, green: 0.68, blue: 0.57, alpha: 1)
    ) {
        root.name = name
        self.coordinateRoot = coordinateRoot

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.7)
        material.metallic = .init(floatLiteral: 0)
        skinMaterial = material
    }

    func entity() -> Entity {
        root
    }

    func clear() {
        root.isEnabled = false
        for entity in jointEntities.values {
            entity.isEnabled = false
        }
        for entity in segmentEntities.values {
            entity.isEnabled = false
        }
        for entity in palmEntities.values {
            entity.isEnabled = false
        }
    }

    func update(hands: [String: [String: simd_float4x4]], relativeTo parent: Entity? = nil) {
        root.isEnabled = true
        let resolvedParent = parent ?? coordinateRoot
        var activeJointKeys = Set<String>()
        var activeSegmentKeys = Set<String>()
        var activePalmKeys = Set<String>()

        for (hand, joints) in hands {
            for jointName in Self.sphereJoints {
                guard let matrix = joints[jointName] else { continue }
                let key = "\(hand)-\(jointName)"
                activeJointKeys.insert(key)
                let sphere = jointEntity(for: key)
                let radius = Self.jointRadius(jointName)
                sphere.setPosition(position(from: matrix), relativeTo: resolvedParent)
                sphere.scale = SIMD3<Float>(repeating: radius)
                sphere.isEnabled = true
            }

            for (start, end) in Self.fingerSegments {
                guard let startMatrix = joints[start],
                      let endMatrix = joints[end]
                else { continue }
                let key = "\(hand)-\(start)-\(end)"
                let segment = segmentEntity(for: key)
                let radius = min(Self.jointRadius(start), Self.jointRadius(end))
                if updateSegment(
                    segment,
                    start: position(from: startMatrix),
                    end: position(from: endMatrix),
                    radius: radius,
                    relativeTo: resolvedParent
                ) {
                    activeSegmentKeys.insert(key)
                }
            }

            if updatePalm(hand: hand, joints: joints, relativeTo: resolvedParent) {
                activePalmKeys.insert(hand)
            }
        }

        for (key, entity) in jointEntities where !activeJointKeys.contains(key) {
            entity.isEnabled = false
        }
        for (key, entity) in segmentEntities where !activeSegmentKeys.contains(key) {
            entity.isEnabled = false
        }
        for (key, entity) in palmEntities where !activePalmKeys.contains(key) {
            entity.isEnabled = false
        }
    }

    private static func jointRadius(_ name: String) -> Float {
        switch name {
        case "wrist": return 0.014
        case "thumbKnuckle": return 0.013
        case "thumbIntermediateBase": return 0.011
        case "thumbIntermediateTip": return 0.0095
        case "thumbTip": return 0.0085
        default: break
        }

        let base: Float
        if name.hasPrefix("little") {
            base = 0.0085
        } else if name.hasPrefix("ring") {
            base = 0.0095
        } else {
            base = 0.010
        }

        if name.hasSuffix("IntermediateTip") {
            return base * 0.85
        }
        if name.hasSuffix("IntermediateBase") {
            return base * 0.92
        }
        if name.hasSuffix("Tip") {
            return base * 0.78
        }
        return base
    }

    private func jointEntity(for key: String) -> ModelEntity {
        if let entity = jointEntities[key] {
            return entity
        }
        let entity = ModelEntity(mesh: unitSphere, materials: [skinMaterial])
        entity.name = "HandJoint-\(key)"
        root.addChild(entity)
        jointEntities[key] = entity
        return entity
    }

    private func segmentEntity(for key: String) -> ModelEntity {
        if let entity = segmentEntities[key] {
            return entity
        }
        let entity = ModelEntity(mesh: unitCylinder, materials: [skinMaterial])
        entity.name = "HandSegment-\(key)"
        root.addChild(entity)
        segmentEntities[key] = entity
        return entity
    }

    private func palmEntity(for hand: String) -> ModelEntity {
        if let entity = palmEntities[hand] {
            return entity
        }
        let entity = ModelEntity(mesh: unitPalm, materials: [skinMaterial])
        entity.name = "HandPalm-\(hand)"
        root.addChild(entity)
        palmEntities[hand] = entity
        return entity
    }

    private func updateSegment(
        _ entity: ModelEntity,
        start: SIMD3<Float>,
        end: SIMD3<Float>,
        radius: Float,
        relativeTo parent: Entity?
    ) -> Bool {
        let delta = end - start
        let length = simd_length(delta)
        guard length.isFinite, length > 0.001 else {
            entity.isEnabled = false
            return false
        }

        entity.setPosition((start + end) * 0.5, relativeTo: parent)
        entity.setOrientation(
            simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta)),
            relativeTo: parent
        )
        entity.scale = SIMD3<Float>(radius, length, radius)
        entity.isEnabled = true
        return true
    }

    private func updatePalm(
        hand: String,
        joints: [String: simd_float4x4],
        relativeTo parent: Entity?
    ) -> Bool {
        guard let wristMatrix = joints["wrist"],
              let indexMatrix = joints["indexFingerKnuckle"],
              let middleMatrix = joints["middleFingerKnuckle"],
              let littleMatrix = joints["littleFingerKnuckle"]
        else {
            palmEntities[hand]?.isEnabled = false
            return false
        }

        let wrist = position(from: wristMatrix)
        let indexKnuckle = position(from: indexMatrix)
        let middleKnuckle = position(from: middleMatrix)
        let littleKnuckle = position(from: littleMatrix)

        let lengthVector = middleKnuckle - wrist
        let widthVector = indexKnuckle - littleKnuckle
        let length = simd_length(lengthVector)
        let width = simd_length(widthVector)
        guard length > 0.01, width > 0.01 else {
            palmEntities[hand]?.isEnabled = false
            return false
        }

        var zAxis = simd_normalize(lengthVector)
        var yAxis = simd_cross(zAxis, simd_normalize(widthVector))
        guard simd_length(yAxis) > 0.001 else {
            palmEntities[hand]?.isEnabled = false
            return false
        }
        yAxis = simd_normalize(yAxis)
        let xAxis = simd_normalize(simd_cross(yAxis, zAxis))
        zAxis = simd_cross(xAxis, yAxis)

        let knuckleCenter = (indexKnuckle + littleKnuckle) * 0.5
        let center = (wrist + knuckleCenter) * 0.5

        let palm = palmEntity(for: hand)
        palm.setPosition(center, relativeTo: parent)
        palm.setOrientation(
            simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis))),
            relativeTo: parent
        )
        palm.scale = SIMD3<Float>(width + 0.024, 0.024, length + 0.012)
        palm.isEnabled = true
        return true
    }
}
