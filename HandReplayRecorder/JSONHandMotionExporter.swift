import Foundation
import simd

protocol AnimationExporter {
    func export(_ recording: HandMotionRecording) throws -> URL
}

struct JSONHandMotionExporter: AnimationExporter {
    func export(_ recording: HandMotionRecording) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "LPVT-HandMotion-\(timestamp).lpvt-handmotion.json"
        let url = documents.appendingPathComponent(filename)
        var writer = CompactHandMotionJSONWriter()
        let data = writer.data(for: recording)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private struct CompactHandMotionJSONWriter {
    private var json = ""
    private let jointNames = HandJointCatalog.jointNames
    private let numberLocale = Locale(identifier: "en_US_POSIX")

    mutating func data(for recording: HandMotionRecording) -> Data {
        appendObjectStart()
        appendKey("schema_version")
        appendInteger(2)
        appendSeparator()
        appendKey("app_name")
        appendString(recording.appName)
        appendSeparator()
        appendKey("created_at")
        appendString(recording.createdAt)
        appendSeparator()
        appendKey("nominal_frame_rate")
        appendNumber(recording.nominalFrameRate)
        appendSeparator()
        appendKey("duration")
        appendNumber(recording.duration)
        appendSeparator()
        appendKey("transform_encoding")
        appendString("[[translation_xyz],[rotation_xyzw]]")
        appendSeparator()
        appendKey("hand_fields")
        appendStringArray([
            "chirality",
            "is_tracked",
            "world_from_hand_anchor",
            "hand_anchor_from_joint",
            "world_from_joint",
            "manikin_from_joint",
            "landmark_from_joint"
        ])
        appendSeparator()
        appendKey("joint_names")
        appendStringArray(jointNames)
        appendSeparator()
        appendKey("manikin_reference")
        appendManikinReference(recording.manikinReference)
        appendSeparator()
        appendKey("frames")
        appendFrames(recording.frames)
        appendObjectEnd()

        return Data(json.utf8)
    }

    private mutating func appendManikinReference(_ reference: ExportedManikinReference) {
        appendObjectStart()
        appendKey("is_locked")
        appendBool(reference.isLocked)
        appendSeparator()
        appendKey("source_reference_object")
        appendString(reference.sourceReferenceObject)
        appendSeparator()
        appendKey("coordinate_frame")
        appendString(reference.coordinateFrame)
        appendSeparator()
        appendKey("world_from_object")
        appendTransform(reference.worldFromObject)
        appendSeparator()
        appendKey("world_from_anchor_to_track")
        appendTransform(reference.worldFromAnchorToTrack)
        appendSeparator()
        appendKey("world_from_landmark")
        appendOptionalTransform(reference.worldFromLandmark)
        appendObjectEnd()
    }

    private mutating func appendFrames(_ frames: [RecordedHandFrame]) {
        appendArrayStart()
        for (index, frame) in frames.enumerated() {
            if index > 0 { appendSeparator() }
            appendArrayStart()
            appendNumber(frame.timestamp)
            appendSeparator()
            appendHands(frame.hands)
            appendArrayEnd()
        }
        appendArrayEnd()
    }

    private mutating func appendHands(_ hands: [RecordedHand]) {
        appendArrayStart()
        for (index, hand) in hands.enumerated() {
            if index > 0 { appendSeparator() }
            appendHand(hand)
        }
        appendArrayEnd()
    }

    private mutating func appendHand(_ hand: RecordedHand) {
        appendArrayStart()
        appendString(hand.chirality)
        appendSeparator()
        appendBool(hand.isTracked)
        appendSeparator()
        appendTransform(hand.worldFromHandAnchor)
        appendSeparator()
        appendJointTransformArray(hand.handAnchorFromJoint)
        appendSeparator()
        appendJointTransformArray(hand.worldFromJoint)
        appendSeparator()
        appendJointTransformArray(hand.manikinFromJoint)
        appendSeparator()
        if let landmarkFromJoint = hand.landmarkFromJoint {
            appendJointTransformArray(landmarkFromJoint)
        } else {
            appendNull()
        }
        appendArrayEnd()
    }

    private mutating func appendJointTransformArray(_ joints: [String: Matrix4x4Value]) {
        appendArrayStart()
        for (index, jointName) in jointNames.enumerated() {
            if index > 0 { appendSeparator() }
            appendOptionalTransform(joints[jointName])
        }
        appendArrayEnd()
    }

    private mutating func appendOptionalTransform(_ transform: Matrix4x4Value?) {
        if let transform {
            appendTransform(transform)
        } else {
            appendNull()
        }
    }

    private mutating func appendTransform(_ transform: Matrix4x4Value) {
        let matrix = transform.matrix
        let translation = SIMD3<Double>(
            Double(matrix.columns.3.x),
            Double(matrix.columns.3.y),
            Double(matrix.columns.3.z)
        )
        let rotation = quaternion(from: matrix)

        appendArrayStart()
        appendNumberArray([translation.x, translation.y, translation.z])
        appendSeparator()
        appendNumberArray([
            Double(rotation.imag.x),
            Double(rotation.imag.y),
            Double(rotation.imag.z),
            Double(rotation.real)
        ])
        appendArrayEnd()
    }

    private func quaternion(from matrix: simd_float4x4) -> simd_quatf {
        let rotationMatrix = simd_float3x3(
            SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
        return simd_normalize(simd_quatf(rotationMatrix))
    }

    private mutating func appendNumberArray(_ values: [Double]) {
        appendArrayStart()
        for (index, value) in values.enumerated() {
            if index > 0 { appendSeparator() }
            appendNumber(value)
        }
        appendArrayEnd()
    }

    private mutating func appendStringArray(_ values: [String]) {
        appendArrayStart()
        for (index, value) in values.enumerated() {
            if index > 0 { appendSeparator() }
            appendString(value)
        }
        appendArrayEnd()
    }

    private mutating func appendKey(_ key: String) {
        appendString(key)
        json.append(":")
    }

    private mutating func appendString(_ value: String) {
        json.append("\"")
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                json.append("\\\"")
            case 0x5C:
                json.append("\\\\")
            case 0x08:
                json.append("\\b")
            case 0x0C:
                json.append("\\f")
            case 0x0A:
                json.append("\\n")
            case 0x0D:
                json.append("\\r")
            case 0x09:
                json.append("\\t")
            case 0x00...0x1F:
                json.append(String(format: "\\u%04X", scalar.value))
            default:
                json.unicodeScalars.append(scalar)
            }
        }
        json.append("\"")
    }

    private mutating func appendNumber(_ value: Double) {
        let truncated = truncate(value, decimalPlaces: 4)
        json.append(String(format: "%.4f", locale: numberLocale, truncated))
    }

    private func truncate(_ value: Double, decimalPlaces: Int) -> Double {
        guard value.isFinite else { return 0 }
        let multiplier = pow(10.0, Double(decimalPlaces))
        let truncated = (value * multiplier).rounded(.towardZero) / multiplier
        return truncated == 0 ? 0 : truncated
    }

    private mutating func appendInteger(_ value: Int) {
        json.append(String(value))
    }

    private mutating func appendBool(_ value: Bool) {
        json.append(value ? "true" : "false")
    }

    private mutating func appendNull() {
        json.append("null")
    }

    private mutating func appendSeparator() {
        json.append(",")
    }

    private mutating func appendObjectStart() {
        json.append("{")
    }

    private mutating func appendObjectEnd() {
        json.append("}")
    }

    private mutating func appendArrayStart() {
        json.append("[")
    }

    private mutating func appendArrayEnd() {
        json.append("]")
    }
}
