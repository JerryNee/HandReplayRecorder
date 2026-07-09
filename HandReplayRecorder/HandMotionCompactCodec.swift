import Foundation
import simd

enum HandMotionCompactCodec {
    static let schemaVersion = 2
    static let transformEncoding = "translation_xyz"
    static let handFields = ["chirality", "is_tracked", "manikin_from_joint"]

    private static let decimalScale: Float = 10_000
    private static let defaultPositionThreshold: Float = 0.0003
    private static let defaultMaxKeyframeGap: TimeInterval = 1.0 / 40.0

    static func exportData(
        from recording: HandMotionRecording,
        thinKeyframes: Bool = true,
        positionThreshold: Float = defaultPositionThreshold,
        maxKeyframeGap: TimeInterval = defaultMaxKeyframeGap
    ) throws -> Data {
        let frames = thinKeyframes
            ? thinFrames(
                recording.frames,
                jointNames: recording.jointNames,
                positionThreshold: positionThreshold,
                maxKeyframeGap: maxKeyframeGap
            )
            : recording.frames

        let document = CompactExportDocument(
            appName: recording.appName,
            createdAt: recording.createdAt,
            nominalFrameRate: recording.nominalFrameRate,
            duration: recording.duration,
            jointNames: recording.jointNames,
            manikinReference: CompactManikinReference(recording.manikinReference),
            frames: frames.map { CompactFrame(frame: $0, jointNames: recording.jointNames) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return try encoder.encode(document)
    }

    static func thinFrames(
        _ frames: [RecordedHandFrame],
        jointNames: [String],
        positionThreshold: Float,
        maxKeyframeGap: TimeInterval
    ) -> [RecordedHandFrame] {
        guard let first = frames.first else { return [] }

        var output: [RecordedHandFrame] = [first]
        var lastKeptTime = first.timestamp
        var lastKeptPositions = positionsByChirality(in: first, jointNames: jointNames)

        for index in 1..<frames.count {
            let frame = frames[index]
            let isLast = index == frames.count - 1
            let elapsed = frame.timestamp - lastKeptTime
            let currentPositions = positionsByChirality(in: frame, jointNames: jointNames)
            let movedEnough = hasSignificantMotion(
                from: lastKeptPositions,
                to: currentPositions,
                threshold: positionThreshold
            )

            if isLast || movedEnough || elapsed >= maxKeyframeGap {
                output.append(frame)
                lastKeptTime = frame.timestamp
                lastKeptPositions = currentPositions
            }
        }

        return output
    }

    private static func positionsByChirality(
        in frame: RecordedHandFrame,
        jointNames: [String]
    ) -> [String: [SIMD3<Float>]] {
        var output: [String: [SIMD3<Float>]] = [:]
        for hand in frame.hands {
            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(jointNames.count)
            for jointName in jointNames {
                if let matrix = hand.manikinFromJoint[jointName]?.matrix {
                    positions.append(position(from: matrix))
                } else {
                    positions.append(SIMD3<Float>(repeating: .nan))
                }
            }
            output[hand.chirality] = positions
        }
        return output
    }

    private static func hasSignificantMotion(
        from lhs: [String: [SIMD3<Float>]],
        to rhs: [String: [SIMD3<Float>]],
        threshold: Float
    ) -> Bool {
        let chiralities = Set(lhs.keys).union(rhs.keys)
        let thresholdSquared = threshold * threshold

        for chirality in chiralities {
            guard let left = lhs[chirality], let right = rhs[chirality] else {
                return true
            }

            let count = min(left.count, right.count)
            for index in 0..<count {
                let delta = right[index] - left[index]
                if delta.x.isNaN || delta.y.isNaN || delta.z.isNaN {
                    return true
                }
                if simd_length_squared(delta) > thresholdSquared {
                    return true
                }
            }
        }

        return false
    }

    static func round(_ value: Float) -> Float {
        (value * decimalScale).rounded() / decimalScale
    }

    static func round(_ value: TimeInterval) -> Double {
        let scaled = value * Double(decimalScale)
        return scaled.rounded() / Double(decimalScale)
    }

    private static func compactTranslation(_ matrix: simd_float4x4) -> [Float] {
        let translation = position(from: matrix)
        return [round(translation.x), round(translation.y), round(translation.z)]
    }

    private static func compactTransform(_ matrix: simd_float4x4) -> [[Float]] {
        let translation = position(from: matrix)
        let rotation = simd_quatf(matrix)
        return [
            [round(translation.x), round(translation.y), round(translation.z)],
            [
                round(rotation.vector.x),
                round(rotation.vector.y),
                round(rotation.vector.z),
                round(rotation.vector.w),
            ],
        ]
    }
}

private struct CompactExportDocument: Encodable {
    let schemaVersion = HandMotionCompactCodec.schemaVersion
    let transformEncoding = HandMotionCompactCodec.transformEncoding
    let handFields = HandMotionCompactCodec.handFields
    let appName: String
    let createdAt: String
    let nominalFrameRate: Double
    let duration: TimeInterval
    let jointNames: [String]
    let manikinReference: CompactManikinReference
    let frames: [CompactFrame]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case transformEncoding = "transform_encoding"
        case handFields = "hand_fields"
        case appName = "app_name"
        case createdAt = "created_at"
        case nominalFrameRate = "nominal_frame_rate"
        case duration
        case jointNames = "joint_names"
        case manikinReference = "manikin_reference"
        case frames
    }
}

private struct CompactManikinReference: Encodable {
    let isLocked: Bool
    let sourceReferenceObject: String
    let coordinateFrame: String
    let worldFromObject: [[Float]]
    let worldFromAnchorToTrack: [[Float]]
    let worldFromLandmark: [[Float]]?

    enum CodingKeys: String, CodingKey {
        case isLocked = "is_locked"
        case sourceReferenceObject = "source_reference_object"
        case coordinateFrame = "coordinate_frame"
        case worldFromObject = "world_from_object"
        case worldFromAnchorToTrack = "world_from_anchor_to_track"
        case worldFromLandmark = "world_from_landmark"
    }

    init(_ reference: ExportedManikinReference) {
        isLocked = reference.isLocked
        sourceReferenceObject = reference.sourceReferenceObject
        coordinateFrame = reference.coordinateFrame
        worldFromObject = compactTRS(reference.worldFromObject.matrix)
        worldFromAnchorToTrack = compactTRS(reference.worldFromAnchorToTrack.matrix)
        worldFromLandmark = reference.worldFromLandmark.map { compactTRS($0.matrix) }
    }
}

private struct CompactFrame: Encodable {
    let timestamp: TimeInterval
    let hands: [CompactHand]

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(HandMotionCompactCodec.round(timestamp))
        try container.encode(hands)
    }
}

private struct CompactHand: Encodable {
    let chirality: String
    let isTracked: Bool
    let jointPositions: [[Float]?]

    init(hand: RecordedHand, jointNames: [String]) {
        chirality = hand.chirality
        isTracked = hand.isTracked
        jointPositions = jointNames.map { jointName in
            hand.manikinFromJoint[jointName].map { matrix in
                let translation = position(from: matrix.matrix)
                return [
                    HandMotionCompactCodec.round(translation.x),
                    HandMotionCompactCodec.round(translation.y),
                    HandMotionCompactCodec.round(translation.z),
                ]
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(chirality)
        try container.encode(isTracked)
        try container.encode(jointPositions)
    }
}

private extension CompactFrame {
    init(frame: RecordedHandFrame, jointNames: [String]) {
        timestamp = frame.timestamp
        hands = frame.hands.map { CompactHand(hand: $0, jointNames: jointNames) }
    }
}

private func compactTRS(_ matrix: simd_float4x4) -> [[Float]] {
    let translation = position(from: matrix)
    let rotation = simd_quatf(matrix)
    return [
        [
            HandMotionCompactCodec.round(translation.x),
            HandMotionCompactCodec.round(translation.y),
            HandMotionCompactCodec.round(translation.z),
        ],
        [
            HandMotionCompactCodec.round(rotation.vector.x),
            HandMotionCompactCodec.round(rotation.vector.y),
            HandMotionCompactCodec.round(rotation.vector.z),
            HandMotionCompactCodec.round(rotation.vector.w),
        ],
    ]
}
