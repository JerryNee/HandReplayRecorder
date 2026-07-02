import Foundation
import simd

struct Matrix4x4Value: Codable, Sendable {
    let values: [Float]

    init(_ matrix: simd_float4x4) {
        values = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    var matrix: simd_float4x4 {
        guard values.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        )
    }
}

struct HandMotionRecording: Codable, Sendable {
    let schemaVersion: Int
    let appName: String
    let createdAt: String
    let nominalFrameRate: Double
    let duration: TimeInterval
    let jointNames: [String]
    let manikinReference: ExportedManikinReference
    let frames: [RecordedHandFrame]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appName = "app_name"
        case createdAt = "created_at"
        case nominalFrameRate = "nominal_frame_rate"
        case duration
        case jointNames = "joint_names"
        case manikinReference = "manikin_reference"
        case frames
    }
}

struct ExportedManikinReference: Codable, Sendable {
    let isLocked: Bool
    let sourceReferenceObject: String
    let coordinateFrame: String
    let worldFromObject: Matrix4x4Value
    let worldFromAnchorToTrack: Matrix4x4Value
    let worldFromLandmark: Matrix4x4Value?

    enum CodingKeys: String, CodingKey {
        case isLocked = "is_locked"
        case sourceReferenceObject = "source_reference_object"
        case coordinateFrame = "coordinate_frame"
        case worldFromObject = "world_from_object"
        case worldFromAnchorToTrack = "world_from_anchor_to_track"
        case worldFromLandmark = "world_from_landmark"
    }
}

struct RecordedHandFrame: Codable, Sendable {
    let timestamp: TimeInterval
    let hands: [RecordedHand]
}

struct RecordedHand: Codable, Sendable {
    let chirality: String
    let isTracked: Bool
    let worldFromHandAnchor: Matrix4x4Value
    let handAnchorFromJoint: [String: Matrix4x4Value]
    let worldFromJoint: [String: Matrix4x4Value]
    let manikinFromJoint: [String: Matrix4x4Value]
    let landmarkFromJoint: [String: Matrix4x4Value]?

    enum CodingKeys: String, CodingKey {
        case chirality
        case isTracked = "is_tracked"
        case worldFromHandAnchor = "world_from_hand_anchor"
        case handAnchorFromJoint = "hand_anchor_from_joint"
        case worldFromJoint = "world_from_joint"
        case manikinFromJoint = "manikin_from_joint"
        case landmarkFromJoint = "landmark_from_joint"
    }
}

struct ManikinReferenceRuntime: Sendable {
    let isLocked: Bool
    let sourceReferenceObject: String
    let coordinateFrame: String
    let worldFromObject: simd_float4x4
    let worldFromAnchorToTrack: simd_float4x4
    let worldFromLandmark: simd_float4x4?

    var exported: ExportedManikinReference {
        ExportedManikinReference(
            isLocked: isLocked,
            sourceReferenceObject: sourceReferenceObject,
            coordinateFrame: coordinateFrame,
            worldFromObject: Matrix4x4Value(worldFromObject),
            worldFromAnchorToTrack: Matrix4x4Value(worldFromAnchorToTrack),
            worldFromLandmark: worldFromLandmark.map(Matrix4x4Value.init)
        )
    }
}

struct LiveHandSnapshot {
    let chirality: String
    let timestamp: TimeInterval
    let worldFromHandAnchor: simd_float4x4
    let handAnchorFromJoint: [String: simd_float4x4]
    let worldFromJoint: [String: simd_float4x4]
}

enum HandReplayError: LocalizedError {
    case simulatorUnsupported(String)
    case missingRealityContent(String)
    case missingReferenceObject
    case noManikinAnchorToLock
    case manikinAnchorRequired
    case noHandTrackingData

    var errorDescription: String? {
        switch self {
        case .simulatorUnsupported(let feature):
            return "\(feature) requires a physical Apple Vision Pro. The simulator can build and open the UI, but it cannot provide this tracking data."
        case .missingRealityContent(let name):
            return "Missing RealityKit content: \(name)."
        case .missingReferenceObject:
            return "LPVT-Simulator.referenceobject was not found in the RealityKitContent package."
        case .noManikinAnchorToLock:
            return "No tracked manikin anchor is available to lock yet."
        case .manikinAnchorRequired:
            return "A locked manikin anchor is required before recording or replaying."
        case .noHandTrackingData:
            return "No hand tracking samples were captured."
        }
    }
}
