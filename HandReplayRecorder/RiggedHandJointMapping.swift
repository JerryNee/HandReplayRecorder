import Foundation

/// Maps joints from `RiggedHand.usdc` to ARKit `HandJointCatalog` names.
enum RiggedHandJointMapping {
    enum DriveMode {
        /// Finger-chain root: entity is already at the ARKit wrist.
        case wristRoot
        /// Metacarpal bone: keep authored palm fan-out, drive length from ARKit.
        case metacarpal
        /// Phalanges: full ARKit local transform.
        case finger
    }

    struct BoneMapping {
        let rigJointSuffix: String
        let arkitJoint: String
        let arkitParent: String?
        let driveMode: DriveMode
    }

    /// Suffixes match names authored in `RiggedHand.usdc` regardless of USD path prefix.
    static let boneMappings: [BoneMapping] = [
        BoneMapping(rigJointSuffix: "MiddleWrist", arkitJoint: "wrist", arkitParent: nil, driveMode: .wristRoot),
        BoneMapping(rigJointSuffix: "Middle_Hand", arkitJoint: "middleFingerMetacarpal", arkitParent: "wrist", driveMode: .metacarpal),
        BoneMapping(rigJointSuffix: "MiddleStart", arkitJoint: "middleFingerKnuckle", arkitParent: "middleFingerMetacarpal", driveMode: .finger),
        BoneMapping(rigJointSuffix: "MiddleMiddle", arkitJoint: "middleFingerIntermediateBase", arkitParent: "middleFingerKnuckle", driveMode: .finger),
        BoneMapping(rigJointSuffix: "MiddleEnd", arkitJoint: "middleFingerIntermediateTip", arkitParent: "middleFingerIntermediateBase", driveMode: .finger),
        BoneMapping(rigJointSuffix: "MiddleEnd_end", arkitJoint: "middleFingerTip", arkitParent: "middleFingerIntermediateTip", driveMode: .finger),

        BoneMapping(rigJointSuffix: "RingWrist", arkitJoint: "wrist", arkitParent: nil, driveMode: .wristRoot),
        BoneMapping(rigJointSuffix: "RingHand", arkitJoint: "ringFingerMetacarpal", arkitParent: "wrist", driveMode: .metacarpal),
        BoneMapping(rigJointSuffix: "RIngStart", arkitJoint: "ringFingerKnuckle", arkitParent: "ringFingerMetacarpal", driveMode: .finger),
        BoneMapping(rigJointSuffix: "RingMiddle", arkitJoint: "ringFingerIntermediateBase", arkitParent: "ringFingerKnuckle", driveMode: .finger),
        BoneMapping(rigJointSuffix: "RingEnd", arkitJoint: "ringFingerIntermediateTip", arkitParent: "ringFingerIntermediateBase", driveMode: .finger),
        BoneMapping(rigJointSuffix: "RingEnd_end", arkitJoint: "ringFingerTip", arkitParent: "ringFingerIntermediateTip", driveMode: .finger),

        BoneMapping(rigJointSuffix: "PointerWrist", arkitJoint: "wrist", arkitParent: nil, driveMode: .wristRoot),
        BoneMapping(rigJointSuffix: "PointerHand", arkitJoint: "indexFingerMetacarpal", arkitParent: "wrist", driveMode: .metacarpal),
        BoneMapping(rigJointSuffix: "PointerStart", arkitJoint: "indexFingerKnuckle", arkitParent: "indexFingerMetacarpal", driveMode: .finger),
        BoneMapping(rigJointSuffix: "PointerMiddle", arkitJoint: "indexFingerIntermediateBase", arkitParent: "indexFingerKnuckle", driveMode: .finger),
        BoneMapping(rigJointSuffix: "PointerEnd", arkitJoint: "indexFingerIntermediateTip", arkitParent: "indexFingerIntermediateBase", driveMode: .finger),
        BoneMapping(rigJointSuffix: "PointerEnd_end", arkitJoint: "indexFingerTip", arkitParent: "indexFingerIntermediateTip", driveMode: .finger),

        BoneMapping(rigJointSuffix: "ThumbWrist", arkitJoint: "wrist", arkitParent: nil, driveMode: .wristRoot),
        BoneMapping(rigJointSuffix: "ThumbHand", arkitJoint: "thumbKnuckle", arkitParent: "wrist", driveMode: .metacarpal),
        BoneMapping(rigJointSuffix: "ThumbStart", arkitJoint: "thumbIntermediateBase", arkitParent: "thumbKnuckle", driveMode: .finger),
        BoneMapping(rigJointSuffix: "ThumbENd", arkitJoint: "thumbIntermediateTip", arkitParent: "thumbIntermediateBase", driveMode: .finger),
        BoneMapping(rigJointSuffix: "ThumbENd_end", arkitJoint: "thumbTip", arkitParent: "thumbIntermediateTip", driveMode: .finger),

        BoneMapping(rigJointSuffix: "PinkyWrist", arkitJoint: "wrist", arkitParent: nil, driveMode: .wristRoot),
        BoneMapping(rigJointSuffix: "PinkyHand", arkitJoint: "littleFingerMetacarpal", arkitParent: "wrist", driveMode: .metacarpal),
        BoneMapping(rigJointSuffix: "PinkyStart", arkitJoint: "littleFingerKnuckle", arkitParent: "littleFingerMetacarpal", driveMode: .finger),
        BoneMapping(rigJointSuffix: "PinkyMiddle", arkitJoint: "littleFingerIntermediateBase", arkitParent: "littleFingerKnuckle", driveMode: .finger),
        BoneMapping(rigJointSuffix: "PinkyEnd", arkitJoint: "littleFingerIntermediateTip", arkitParent: "littleFingerIntermediateBase", driveMode: .finger),
        BoneMapping(rigJointSuffix: "PinkyEnd_end", arkitJoint: "littleFingerTip", arkitParent: "littleFingerIntermediateTip", driveMode: .finger),
    ]

    static func jointIndex(in jointNames: [String], matching suffix: String) -> Int? {
        if let exact = jointNames.firstIndex(of: suffix) {
            return exact
        }
        return jointNames.firstIndex { $0.hasSuffix("/\(suffix)") || $0.hasSuffix(suffix) }
    }
}
