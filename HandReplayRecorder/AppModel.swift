import Foundation
import Observation
import RealityKit

@MainActor
@Observable
final class AppModel {
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    let immersiveSpaceID = "HandReplayRecorderSpace"
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var lastExportedURL: URL?
    var lastError: String?

    let manikinTracker = ManikinTracker()
    let recorder = HandTrackingRecorder()

    var canRecord: Bool {
        immersiveSpaceState == .open
            && manikinTracker.lockedReference != nil
            && !recorder.isRecording
            && !recorder.isPlaying
    }

    var canStop: Bool {
        recorder.isRecording || recorder.isPlaying
    }

    var canPlay: Bool {
        recorder.currentRecording != nil && !recorder.isRecording && !recorder.isPlaying
    }

    var canExport: Bool {
        recorder.currentRecording != nil && !recorder.isRecording
    }

    func configureReality(root: Entity) async {
        await manikinTracker.configureReality(root: root)
        await recorder.configureReality(root: root)
    }

    func startFindingManikin() async {
        lastError = nil
        do {
            try await manikinTracker.startTracking()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func lockManikin() {
        lastError = nil
        do {
            try manikinTracker.lockCurrentReference()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startRecording() async {
        lastError = nil
        guard let reference = manikinTracker.lockedReference else {
            lastError = "Lock the manikin anchor before recording."
            return
        }

        do {
            try await recorder.startTracking()
            try recorder.startRecording(reference: reference)
            lastExportedURL = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        recorder.stop()
    }

    func play() {
        lastError = nil
        guard let reference = manikinTracker.lockedReference else {
            lastError = "Lock the manikin anchor before playback."
            return
        }
        recorder.play(anchoredTo: reference)
    }

    func clear() {
        recorder.clear()
        lastExportedURL = nil
        lastError = nil
    }

    func exportRecording() {
        lastError = nil
        guard let recording = recorder.currentRecording else {
            lastError = "There is no recording to export."
            return
        }

        do {
            lastExportedURL = try JSONHandMotionExporter().export(recording)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopImmersiveWork() {
        recorder.stop()
        recorder.stopTracking()
        manikinTracker.stopTracking()
    }
}
