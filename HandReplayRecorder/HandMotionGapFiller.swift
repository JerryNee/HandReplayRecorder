import Foundation
import simd

/// Bridges short tracking dropouts in a recording for playback.
///
/// ARKit marks joints untracked during brief occlusions, so recorded frames
/// have holes that make the replayed hand blink. This fills any per-joint gap
/// shorter than `maxGap` by interpolating `manikin_from_joint` positions
/// between the surrounding samples. Longer gaps are left alone: the hand
/// genuinely disappears rather than pretending stale data is real. Synthesized
/// hands are marked `isTracked: false` and only used for playback, never
/// exported.
enum HandMotionGapFiller {
    static func fill(_ frames: [RecordedHandFrame], maxGap: TimeInterval = 0.3) -> [RecordedHandFrame] {
        struct Sample {
            let frameIndex: Int
            let time: TimeInterval
            let position: SIMD3<Float>
        }

        // frame index -> chirality -> joint -> interpolated position
        var additions: [Int: [String: [String: SIMD3<Float>]]] = [:]
        let chiralities = Set(frames.flatMap { $0.hands.map(\.chirality) })

        for chirality in chiralities {
            var samplesByJoint: [String: [Sample]] = [:]
            for (frameIndex, frame) in frames.enumerated() {
                guard let hand = frame.hands.first(where: { $0.chirality == chirality }) else { continue }
                for (jointName, value) in hand.manikinFromJoint {
                    samplesByJoint[jointName, default: []].append(
                        Sample(frameIndex: frameIndex, time: frame.timestamp, position: position(from: value.matrix))
                    )
                }
            }

            for (jointName, samples) in samplesByJoint {
                guard samples.count > 1 else { continue }
                for index in 0..<(samples.count - 1) {
                    let start = samples[index]
                    let end = samples[index + 1]
                    guard end.frameIndex > start.frameIndex + 1,
                          end.time - start.time <= maxGap,
                          end.time > start.time
                    else { continue }
                    for gapIndex in (start.frameIndex + 1)..<end.frameIndex {
                        let factor = Float((frames[gapIndex].timestamp - start.time) / (end.time - start.time))
                        additions[gapIndex, default: [:]][chirality, default: [:]][jointName] =
                            simd_mix(start.position, end.position, SIMD3<Float>(repeating: factor))
                    }
                }
            }
        }

        guard !additions.isEmpty else { return frames }

        var output = frames
        for (frameIndex, byChirality) in additions {
            var hands = output[frameIndex].hands
            for (chirality, joints) in byChirality {
                if let handIndex = hands.firstIndex(where: { $0.chirality == chirality }) {
                    let hand = hands[handIndex]
                    var manikinFromJoint = hand.manikinFromJoint
                    for (jointName, jointPosition) in joints where manikinFromJoint[jointName] == nil {
                        manikinFromJoint[jointName] = Matrix4x4Value(translationMatrix(jointPosition))
                    }
                    hands[handIndex] = RecordedHand(
                        chirality: hand.chirality,
                        isTracked: hand.isTracked,
                        worldFromHandAnchor: hand.worldFromHandAnchor,
                        handAnchorFromJoint: hand.handAnchorFromJoint,
                        worldFromJoint: hand.worldFromJoint,
                        manikinFromJoint: manikinFromJoint,
                        landmarkFromJoint: hand.landmarkFromJoint
                    )
                } else {
                    var manikinFromJoint: [String: Matrix4x4Value] = [:]
                    for (jointName, jointPosition) in joints {
                        manikinFromJoint[jointName] = Matrix4x4Value(translationMatrix(jointPosition))
                    }
                    hands.append(RecordedHand(
                        chirality: chirality,
                        isTracked: false,
                        worldFromHandAnchor: Matrix4x4Value(matrix_identity_float4x4),
                        handAnchorFromJoint: [:],
                        worldFromJoint: [:],
                        manikinFromJoint: manikinFromJoint,
                        landmarkFromJoint: nil
                    ))
                }
            }
            output[frameIndex] = RecordedHandFrame(timestamp: output[frameIndex].timestamp, hands: hands)
        }
        return output
    }
}
