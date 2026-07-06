import ARKit
import Foundation

enum HandJointCatalog {
    static let trackedJoints: [HandSkeleton.JointName] = [
        .wrist,
        .thumbKnuckle,
        .thumbIntermediateBase,
        .thumbIntermediateTip,
        .thumbTip,
        .indexFingerMetacarpal,
        .indexFingerKnuckle,
        .indexFingerIntermediateBase,
        .indexFingerIntermediateTip,
        .indexFingerTip,
        .middleFingerMetacarpal,
        .middleFingerKnuckle,
        .middleFingerIntermediateBase,
        .middleFingerIntermediateTip,
        .middleFingerTip,
        .ringFingerMetacarpal,
        .ringFingerKnuckle,
        .ringFingerIntermediateBase,
        .ringFingerIntermediateTip,
        .ringFingerTip,
        .littleFingerMetacarpal,
        .littleFingerKnuckle,
        .littleFingerIntermediateBase,
        .littleFingerIntermediateTip,
        .littleFingerTip
    ]

    static let jointNames: [String] = trackedJoints.map(name)

    static let bonePairs: [(String, String)] = [
        ("wrist", "thumbKnuckle"),
        ("thumbKnuckle", "thumbIntermediateBase"),
        ("thumbIntermediateBase", "thumbIntermediateTip"),
        ("thumbIntermediateTip", "thumbTip"),
        ("wrist", "indexFingerMetacarpal"),
        ("indexFingerMetacarpal", "indexFingerKnuckle"),
        ("indexFingerKnuckle", "indexFingerIntermediateBase"),
        ("indexFingerIntermediateBase", "indexFingerIntermediateTip"),
        ("indexFingerIntermediateTip", "indexFingerTip"),
        ("wrist", "middleFingerMetacarpal"),
        ("middleFingerMetacarpal", "middleFingerKnuckle"),
        ("middleFingerKnuckle", "middleFingerIntermediateBase"),
        ("middleFingerIntermediateBase", "middleFingerIntermediateTip"),
        ("middleFingerIntermediateTip", "middleFingerTip"),
        ("wrist", "ringFingerMetacarpal"),
        ("ringFingerMetacarpal", "ringFingerKnuckle"),
        ("ringFingerKnuckle", "ringFingerIntermediateBase"),
        ("ringFingerIntermediateBase", "ringFingerIntermediateTip"),
        ("ringFingerIntermediateTip", "ringFingerTip"),
        ("wrist", "littleFingerMetacarpal"),
        ("littleFingerMetacarpal", "littleFingerKnuckle"),
        ("littleFingerKnuckle", "littleFingerIntermediateBase"),
        ("littleFingerIntermediateBase", "littleFingerIntermediateTip"),
        ("littleFingerIntermediateTip", "littleFingerTip")
    ]

    static let parentByJointName: [String: String] = Dictionary(uniqueKeysWithValues: bonePairs.map { ($0.1, $0.0) })

    static func parentName(of jointName: String) -> String? {
        parentByJointName[jointName]
    }

    static func name(_ jointName: HandSkeleton.JointName) -> String {
        switch jointName {
        case .wrist: return "wrist"
        case .forearmWrist: return "forearmWrist"
        case .forearmArm: return "forearmArm"
        case .thumbKnuckle: return "thumbKnuckle"
        case .thumbIntermediateBase: return "thumbIntermediateBase"
        case .thumbIntermediateTip: return "thumbIntermediateTip"
        case .thumbTip: return "thumbTip"
        case .indexFingerMetacarpal: return "indexFingerMetacarpal"
        case .indexFingerKnuckle: return "indexFingerKnuckle"
        case .indexFingerIntermediateBase: return "indexFingerIntermediateBase"
        case .indexFingerIntermediateTip: return "indexFingerIntermediateTip"
        case .indexFingerTip: return "indexFingerTip"
        case .middleFingerMetacarpal: return "middleFingerMetacarpal"
        case .middleFingerKnuckle: return "middleFingerKnuckle"
        case .middleFingerIntermediateBase: return "middleFingerIntermediateBase"
        case .middleFingerIntermediateTip: return "middleFingerIntermediateTip"
        case .middleFingerTip: return "middleFingerTip"
        case .ringFingerMetacarpal: return "ringFingerMetacarpal"
        case .ringFingerKnuckle: return "ringFingerKnuckle"
        case .ringFingerIntermediateBase: return "ringFingerIntermediateBase"
        case .ringFingerIntermediateTip: return "ringFingerIntermediateTip"
        case .ringFingerTip: return "ringFingerTip"
        case .littleFingerMetacarpal: return "littleFingerMetacarpal"
        case .littleFingerKnuckle: return "littleFingerKnuckle"
        case .littleFingerIntermediateBase: return "littleFingerIntermediateBase"
        case .littleFingerIntermediateTip: return "littleFingerIntermediateTip"
        case .littleFingerTip: return "littleFingerTip"
        @unknown default: return "\(jointName)"
        }
    }
}
