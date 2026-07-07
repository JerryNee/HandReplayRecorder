import Foundation
import RealityKit
import SwiftUI

/// Renders hands as realistic skinned meshes (WebXR generic-hand models,
/// Apache-2.0, see THIRD_PARTY_LICENSES.md) driven from ARKit joint positions.
///
/// The retargeting is purely positional: every mapped skeleton joint is
/// overwritten each frame with an absolute transform whose translation is the
/// recorded joint position and whose rotation is derived from the bind pose
/// (palm frame for the wrist, per-bone shortest-arc aiming for the fingers).
/// This works with the translation-only matrices produced by replay
/// interpolation and is independent of the asset's bind orientation.
@MainActor
final class HandRigVisualizer: HandVisualizing {
    private let root = Entity()
    private let coordinateRoot: Entity?
    private var rigs: [String: HandRig] = [:]

    private static let assetNames = [
        "left": "GenericHand_left",
        "right": "GenericHand_right"
    ]

    init?(name: String, coordinateRoot: Entity? = nil) async {
        root.name = name
        self.coordinateRoot = coordinateRoot

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.87, green: 0.68, blue: 0.57, alpha: 1))
        material.roughness = .init(floatLiteral: 0.65)
        material.metallic = .init(floatLiteral: 0)

        for (chirality, assetName) in Self.assetNames {
            guard let loaded = try? await Entity(named: assetName),
                  let model = Self.findSkinnedModel(in: loaded)
            else {
                return nil
            }
            // Reparent first, then reset the transform: addChild keeps the
            // local transform, which still contains the loader's up-axis
            // compensation from the original hierarchy.
            root.addChild(model)
            model.transform = Transform()
            if var modelComponent = model.model {
                modelComponent.materials = modelComponent.materials.map { _ in material }
                model.model = modelComponent
            }
            guard let rig = HandRig(model: model) else { return nil }
            rigs[chirality] = rig
        }
    }

    func entity() -> Entity {
        root
    }

    func clear() {
        root.isEnabled = false
        for rig in rigs.values {
            rig.model.isEnabled = false
        }
    }

    func update(hands: [String: [String: simd_float4x4]], relativeTo parent: Entity?) {
        root.isEnabled = true
        if let anchor = parent ?? coordinateRoot {
            root.setTransformMatrix(matrix_identity_float4x4, relativeTo: anchor)
        }

        for (chirality, rig) in rigs {
            guard let joints = hands[chirality] else {
                rig.model.isEnabled = false
                continue
            }
            var positions: [String: SIMD3<Float>] = [:]
            positions.reserveCapacity(joints.count)
            for (jointName, matrix) in joints {
                positions[jointName] = position(from: matrix)
            }
            if rig.apply(positions: positions) {
                rig.model.isEnabled = true
            } else {
                rig.model.isEnabled = false
            }
        }
    }

    private static func findSkinnedModel(in entity: Entity) -> ModelEntity? {
        var queue: [Entity] = [entity]
        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            if let model = candidate as? ModelEntity, !model.jointNames.isEmpty {
                return model
            }
            queue.append(contentsOf: candidate.children)
        }
        return nil
    }
}

/// Maps ARKit hand joints onto one skinned hand model and poses it.
@MainActor
private final class HandRig {
    let model: ModelEntity
    private var modelIndex: [String: Int] = [:]
    private var bindPos: [String: SIMD3<Float>] = [:]
    private var bindRot: [String: simd_quatf] = [:]

    private static let arkitToModel: [String: String] = {
        var map: [String: String] = [
            "wrist": "wrist",
            "thumbKnuckle": "thumb_metacarpal",
            "thumbIntermediateBase": "thumb_phalanx_proximal",
            "thumbIntermediateTip": "thumb_phalanx_distal",
            "thumbTip": "thumb_tip"
        ]
        let fingers = [
            ("indexFinger", "index_finger"),
            ("middleFinger", "middle_finger"),
            ("ringFinger", "ring_finger"),
            ("littleFinger", "pinky_finger")
        ]
        for (arkit, model) in fingers {
            map["\(arkit)Metacarpal"] = "\(model)_metacarpal"
            map["\(arkit)Knuckle"] = "\(model)_phalanx_proximal"
            map["\(arkit)IntermediateBase"] = "\(model)_phalanx_intermediate"
            map["\(arkit)IntermediateTip"] = "\(model)_phalanx_distal"
            map["\(arkit)Tip"] = "\(model)_tip"
        }
        return map
    }()

    private static let fingerChains: [[String]] = [
        ["thumbKnuckle", "thumbIntermediateBase", "thumbIntermediateTip", "thumbTip"],
        ["indexFingerMetacarpal", "indexFingerKnuckle", "indexFingerIntermediateBase", "indexFingerIntermediateTip", "indexFingerTip"],
        ["middleFingerMetacarpal", "middleFingerKnuckle", "middleFingerIntermediateBase", "middleFingerIntermediateTip", "middleFingerTip"],
        ["ringFingerMetacarpal", "ringFingerKnuckle", "ringFingerIntermediateBase", "ringFingerIntermediateTip", "ringFingerTip"],
        ["littleFingerMetacarpal", "littleFingerKnuckle", "littleFingerIntermediateBase", "littleFingerIntermediateTip", "littleFingerTip"]
    ]

    init?(model: ModelEntity) {
        self.model = model
        var indexByModelName: [String: Int] = [:]
        for (index, name) in model.jointNames.enumerated() {
            let leaf = name.split(separator: "/").last.map(String.init) ?? name
            indexByModelName[leaf] = index
        }
        for (arkitName, modelName) in Self.arkitToModel {
            guard let index = indexByModelName[modelName] else { return nil }
            modelIndex[arkitName] = index
            let transform = model.jointTransforms[index]
            bindPos[arkitName] = transform.translation
            bindRot[arkitName] = transform.rotation
        }
    }

    /// Palm-region joints usable for estimating the hand pose. Any 3
    /// non-collinear of these are enough; occluded recordings rarely have all
    /// of them, so the solver picks the best available triangle.
    private static let palmJoints = [
        "wrist", "thumbKnuckle",
        "indexFingerMetacarpal", "middleFingerMetacarpal",
        "ringFingerMetacarpal", "littleFingerMetacarpal",
        "indexFingerKnuckle", "middleFingerKnuckle",
        "ringFingerKnuckle", "littleFingerKnuckle"
    ]

    /// Rigid palm registration: finds the largest-area triangle of tracked
    /// palm joints and returns the rotation delta from bind pose to target,
    /// plus one tracked joint usable as a position anchor.
    private func palmDelta(positions: [String: SIMD3<Float>]) -> (simd_quatf, String)? {
        let available = Self.palmJoints.filter { positions[$0] != nil }
        guard available.count >= 3 else { return nil }

        var triples: [(Float, (String, String, String))] = []
        for i in 0..<(available.count - 2) {
            for j in (i + 1)..<(available.count - 1) {
                for k in (j + 1)..<available.count {
                    let a = bindPos[available[i]]!
                    let b = bindPos[available[j]]!
                    let c = bindPos[available[k]]!
                    let area = simd_length(simd_cross(b - a, c - a))
                    if area > 0.0002 {
                        triples.append((area, (available[i], available[j], available[k])))
                    }
                }
            }
        }
        triples.sort { $0.0 > $1.0 }

        for (_, (n1, n2, n3)) in triples.prefix(8) {
            guard let bindFrame = Self.triangleFrame(bindPos[n1]!, bindPos[n2]!, bindPos[n3]!),
                  let targetFrame = Self.triangleFrame(positions[n1]!, positions[n2]!, positions[n3]!)
            else { continue }
            return (targetFrame * bindFrame.inverse, n1)
        }
        return nil
    }

    private static func triangleFrame(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>) -> simd_quatf? {
        let e1 = p2 - p1
        let e2 = p3 - p1
        guard simd_length(e1) > 0.005 else { return nil }
        let x = simd_normalize(e1)
        let normal = simd_cross(e1, e2)
        guard simd_length(normal) > 0.00001 else { return nil }
        let z = simd_normalize(normal)
        let y = simd_cross(z, x)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }

    /// Poses the skeleton from joint positions given in the model's local
    /// space. Returns false when too few palm joints are tracked to orient
    /// the hand.
    func apply(positions: [String: SIMD3<Float>]) -> Bool {
        guard let (delta, anchorName) = palmDelta(positions: positions) else { return false }

        var transforms = model.jointTransforms
        var outRot: [String: simd_quatf] = [:]
        var outPos: [String: SIMD3<Float>] = [:]

        let wristRot = delta * bindRot["wrist"]!
        let wristTarget = positions["wrist"]
            ?? (positions[anchorName]! + delta.act(bindPos["wrist"]! - bindPos[anchorName]!))
        outRot["wrist"] = wristRot
        outPos["wrist"] = wristTarget
        transforms[modelIndex["wrist"]!] = Transform(rotation: wristRot, translation: wristTarget)

        for chain in Self.fingerChains {
            var parent = "wrist"
            for (offset, joint) in chain.enumerated() {
                let parentDelta = outRot[parent]! * bindRot[parent]!.inverse
                let followRot = parentDelta * bindRot[joint]!
                let followPos = outPos[parent]! + parentDelta.act(bindPos[joint]! - bindPos[parent]!)
                let pos = positions[joint] ?? followPos

                var rot = followRot
                if offset + 1 < chain.count, let childTarget = positions[chain[offset + 1]] {
                    let bindDir = bindPos[chain[offset + 1]]! - bindPos[joint]!
                    let targetDir = childTarget - pos
                    if simd_length(bindDir) > 0.0005, simd_length(targetDir) > 0.0005 {
                        let currentDir = (rot * bindRot[joint]!.inverse).act(simd_normalize(bindDir))
                        rot = Self.shortestArc(currentDir, simd_normalize(targetDir)) * rot
                    }
                }

                outRot[joint] = rot
                outPos[joint] = pos
                transforms[modelIndex[joint]!] = Transform(rotation: rot, translation: pos)
                parent = joint
            }
        }

        model.jointTransforms = transforms
        return true
    }

    private static func shortestArc(_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(from)
        let t = simd_normalize(to)
        let dot = simd_dot(f, t)
        if dot > 0.9999 { return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)) }
        if dot < -0.9999 {
            var axis = simd_cross(f, SIMD3<Float>(1, 0, 0))
            if simd_length(axis) < 0.001 { axis = simd_cross(f, SIMD3<Float>(0, 1, 0)) }
            return simd_quatf(angle: .pi, axis: simd_normalize(axis))
        }
        return simd_quatf(from: f, to: t)
    }
}
