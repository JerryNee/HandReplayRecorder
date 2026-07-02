import ARKit
import Foundation
import Observation
import RealityKit

@MainActor
@Observable
final class HandTrackingRecorder {
    private(set) var isTracking = false
    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var recordedFrameCount = 0
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var statusMessage = "Lock the manikin anchor before recording."
    private(set) var trackedHandsSummary = "none"
    private(set) var currentRecording: HandMotionRecording?

    private var session: ARKitSession?
    private var provider: HandTrackingProvider?
    private var updateTask: Task<Void, Never>?
    private var sampleTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var liveHands: [String: LiveHandSnapshot] = [:]
    private var frames: [RecordedHandFrame] = []
    private var recordingStartTime: Date?
    private var recordingReference: ManikinReferenceRuntime?
    private var liveVisualizer: HandSkeletonVisualizer?
    private var replayVisualizer: HandSkeletonVisualizer?
    private let replayRoot = Entity()

    func configureReality(root: Entity) {
        guard liveVisualizer == nil else { return }
        replayRoot.name = "ReplayRoot-AnchorToTrack"
        root.addChild(replayRoot)

        let live = HandSkeletonVisualizer(name: "LiveHandSkeleton", color: .systemCyan)
        let replay = HandSkeletonVisualizer(name: "ReplayHandSkeleton", coordinateRoot: replayRoot, color: .systemGreen)
        root.addChild(live.entity())
        replayRoot.addChild(replay.entity())
        live.clear()
        replay.clear()
        liveVisualizer = live
        replayVisualizer = replay
    }

    func startTracking() async throws {
        guard !isTracking else { return }

        #if targetEnvironment(simulator)
        throw HandReplayError.simulatorUnsupported("Hand tracking")
        #else
        let provider = HandTrackingProvider()
        let session = ARKitSession()
        self.provider = provider
        self.session = session
        statusMessage = "Starting hand tracking..."
        try await session.run([provider])
        isTracking = true
        statusMessage = "Hand tracking ready."

        updateTask?.cancel()
        updateTask = Task { @MainActor in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                handleHandAnchor(update.anchor)
            }
        }
        #endif
    }

    func stopTracking() {
        updateTask?.cancel()
        updateTask = nil
        sampleTask?.cancel()
        sampleTask = nil
        session?.stop()
        session = nil
        provider = nil
        isTracking = false
        liveHands.removeAll()
        trackedHandsSummary = "none"
        liveVisualizer?.clear()
    }

    func startRecording(reference: ManikinReferenceRuntime) throws {
        guard isTracking else {
            throw HandReplayError.noHandTrackingData
        }
        guard reference.isLocked else {
            throw HandReplayError.manikinAnchorRequired
        }

        stopPlayback()
        frames.removeAll()
        recordedFrameCount = 0
        recordingDuration = 0
        currentRecording = nil
        recordingReference = reference
        recordingStartTime = Date()
        isRecording = true
        statusMessage = "Recording hand motion relative to AnchorToTrack..."

        sampleTask?.cancel()
        sampleTask = Task { @MainActor in
            while !Task.isCancelled && isRecording {
                sampleFrame()
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    func stop() {
        if isRecording {
            finishRecording()
        }
        if isPlaying {
            stopPlayback()
        }
    }

    func play(anchoredTo reference: ManikinReferenceRuntime) {
        guard let recording = currentRecording else {
            statusMessage = "No recording available."
            return
        }

        stopPlayback()
        isPlaying = true
        statusMessage = "Playing manikin-local hand replay..."
        replayRoot.setTransformMatrix(reference.worldFromAnchorToTrack, relativeTo: nil)
        replayRoot.isEnabled = true

        playbackTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > recording.duration {
                    break
                }
                updateReplay(recording: recording, time: elapsed)
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            if !Task.isCancelled {
                updateReplay(recording: recording, time: recording.duration)
            }
            isPlaying = false
            statusMessage = "Playback finished."
        }
    }

    func clear() {
        stop()
        frames.removeAll()
        currentRecording = nil
        recordedFrameCount = 0
        recordingDuration = 0
        recordingReference = nil
        replayVisualizer?.clear()
        statusMessage = "Cleared recording."
    }

    private func handleHandAnchor(_ handAnchor: HandAnchor) {
        let chirality = handAnchor.chirality == .left ? "left" : "right"
        guard handAnchor.isTracked,
              let skeleton = handAnchor.handSkeleton
        else {
            liveHands.removeValue(forKey: chirality)
            refreshLiveVisualization()
            return
        }

        let worldFromHandAnchor = handAnchor.originFromAnchorTransform
        var handAnchorFromJoint: [String: simd_float4x4] = [:]
        var worldFromJoint: [String: simd_float4x4] = [:]

        for jointName in HandJointCatalog.trackedJoints {
            let joint = skeleton.joint(jointName)
            guard joint.isTracked else { continue }
            let name = HandJointCatalog.name(jointName)
            let handFromJoint = joint.anchorFromJointTransform
            handAnchorFromJoint[name] = handFromJoint
            worldFromJoint[name] = worldFromHandAnchor * handFromJoint
        }

        guard !worldFromJoint.isEmpty else {
            liveHands.removeValue(forKey: chirality)
            refreshLiveVisualization()
            return
        }

        liveHands[chirality] = LiveHandSnapshot(
            chirality: chirality,
            timestamp: Date().timeIntervalSinceReferenceDate,
            worldFromHandAnchor: worldFromHandAnchor,
            handAnchorFromJoint: handAnchorFromJoint,
            worldFromJoint: worldFromJoint
        )
        trackedHandsSummary = liveHands.keys.sorted().joined(separator: ", ")
        refreshLiveVisualization()
    }

    private func refreshLiveVisualization() {
        guard !liveHands.isEmpty else {
            trackedHandsSummary = "none"
            liveVisualizer?.clear()
            return
        }

        var hands: [String: [String: simd_float4x4]] = [:]
        for (chirality, snapshot) in liveHands {
            hands[chirality] = snapshot.worldFromJoint
        }
        liveVisualizer?.update(hands: hands, relativeTo: nil)
    }

    private func sampleFrame() {
        guard isRecording,
              let start = recordingStartTime,
              let reference = recordingReference
        else { return }

        let timestamp = Date().timeIntervalSince(start)
        let manikinFromWorld = simd_inverse(reference.worldFromAnchorToTrack)
        let landmarkFromWorld = reference.worldFromLandmark.map { simd_inverse($0) }

        let hands = liveHands.values.sorted { $0.chirality < $1.chirality }.map { liveHand in
            var manikinFromJoint: [String: Matrix4x4Value] = [:]
            var landmarkFromJoint: [String: Matrix4x4Value] = [:]
            var worldFromJoint: [String: Matrix4x4Value] = [:]
            var handAnchorFromJoint: [String: Matrix4x4Value] = [:]

            for (jointName, matrix) in liveHand.worldFromJoint {
                worldFromJoint[jointName] = Matrix4x4Value(matrix)
                manikinFromJoint[jointName] = Matrix4x4Value(manikinFromWorld * matrix)
                if let landmarkFromWorld {
                    landmarkFromJoint[jointName] = Matrix4x4Value(landmarkFromWorld * matrix)
                }
            }

            for (jointName, matrix) in liveHand.handAnchorFromJoint {
                handAnchorFromJoint[jointName] = Matrix4x4Value(matrix)
            }

            return RecordedHand(
                chirality: liveHand.chirality,
                isTracked: true,
                worldFromHandAnchor: Matrix4x4Value(liveHand.worldFromHandAnchor),
                handAnchorFromJoint: handAnchorFromJoint,
                worldFromJoint: worldFromJoint,
                manikinFromJoint: manikinFromJoint,
                landmarkFromJoint: landmarkFromJoint.isEmpty ? nil : landmarkFromJoint
            )
        }

        frames.append(RecordedHandFrame(timestamp: timestamp, hands: hands))
        recordedFrameCount = frames.count
        recordingDuration = timestamp
    }

    private func finishRecording() {
        sampleTask?.cancel()
        sampleTask = nil
        isRecording = false

        guard !frames.isEmpty, let reference = recordingReference else {
            statusMessage = "Recording stopped, but no hand frames were captured."
            return
        }

        let duration = frames.last?.timestamp ?? 0
        currentRecording = HandMotionRecording(
            schemaVersion: 1,
            appName: "HandReplayRecorder",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            nominalFrameRate: 60,
            duration: duration,
            jointNames: HandJointCatalog.jointNames,
            manikinReference: reference.exported,
            frames: frames
        )
        recordingDuration = duration
        statusMessage = "Recording saved in memory. Ready to play or export."
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        replayVisualizer?.clear()
    }

    private func updateReplay(recording: HandMotionRecording, time: TimeInterval) {
        guard let framePair = bracketingFrames(recording.frames, at: time) else {
            replayVisualizer?.clear()
            return
        }

        let hands = interpolatedHands(lhs: framePair.0, rhs: framePair.1, time: time)
        replayVisualizer?.update(hands: hands, relativeTo: replayRoot)
    }

    private func bracketingFrames(_ frames: [RecordedHandFrame], at time: TimeInterval) -> (RecordedHandFrame, RecordedHandFrame)? {
        guard let first = frames.first else { return nil }
        guard time > first.timestamp else { return (first, first) }
        for index in 1..<frames.count {
            if frames[index].timestamp >= time {
                return (frames[index - 1], frames[index])
            }
        }
        guard let last = frames.last else { return nil }
        return (last, last)
    }

    private func interpolatedHands(
        lhs: RecordedHandFrame,
        rhs: RecordedHandFrame,
        time: TimeInterval
    ) -> [String: [String: simd_float4x4]] {
        let factor = clampedInterpolationFactor(currentTime: time, start: lhs.timestamp, end: rhs.timestamp)
        var output: [String: [String: simd_float4x4]] = [:]
        let lhsByHand = Dictionary(uniqueKeysWithValues: lhs.hands.map { ($0.chirality, $0) })
        let rhsByHand = Dictionary(uniqueKeysWithValues: rhs.hands.map { ($0.chirality, $0) })
        let hands = Set(lhsByHand.keys).union(rhsByHand.keys)

        for hand in hands {
            guard let left = lhsByHand[hand] ?? rhsByHand[hand],
                  let right = rhsByHand[hand] ?? lhsByHand[hand]
            else { continue }

            var joints: [String: simd_float4x4] = [:]
            let jointNames = Set(left.manikinFromJoint.keys).union(right.manikinFromJoint.keys)
            for jointName in jointNames {
                guard let lhsMatrix = left.manikinFromJoint[jointName]?.matrix ?? right.manikinFromJoint[jointName]?.matrix,
                      let rhsMatrix = right.manikinFromJoint[jointName]?.matrix ?? left.manikinFromJoint[jointName]?.matrix
                else { continue }

                joints[jointName] = interpolatedTranslationMatrix(lhsMatrix, rhsMatrix, t: factor)
            }
            output[hand] = joints
        }

        return output
    }
}
