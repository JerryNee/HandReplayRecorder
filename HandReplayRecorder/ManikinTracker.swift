import ARKit
import Foundation
import Observation
import RealityKit
import RealityKitContent

@MainActor
@Observable
final class ManikinTracker {
    private(set) var isTracking = false
    private(set) var latestReference: ManikinReferenceRuntime?
    private(set) var lockedReference: ManikinReferenceRuntime?
    private(set) var statusMessage = "Open the immersive space, then find the LPVT manikin."

    private var rootEntity: Entity?
    private var manikinEntity: Entity?
    private var anchorToTrackEntity: Entity?
    private var landmarkEntity: Entity?
    private var session: ARKitSession?
    private var updateTask: Task<Void, Never>?

    func configureReality(root: Entity) async {
        rootEntity = root
        guard manikinEntity == nil else { return }

        do {
            let simTracker = try await Entity(named: "simTracker", in: realityKitContentBundle)
            simTracker.name = "LPVT-Manikin-Reference"
            simTracker.isEnabled = false
            root.addChild(simTracker)
            manikinEntity = simTracker
            anchorToTrackEntity = simTracker.findEntity(named: "AnchorToTrack")
            landmarkEntity = simTracker.findEntity(named: "Landmark")
            if anchorToTrackEntity == nil {
                statusMessage = "simTracker loaded, but AnchorToTrack was not found."
            } else {
                statusMessage = "simTracker loaded. Ready to find manikin."
            }
        } catch {
            statusMessage = "Could not load simTracker from RealityKitContent."
        }
    }

    func startTracking() async throws {
        guard !isTracking else { return }

        #if targetEnvironment(simulator)
        throw HandReplayError.simulatorUnsupported("LPVT manikin object tracking")
        #else
        guard manikinEntity != nil, anchorToTrackEntity != nil else {
            throw HandReplayError.missingRealityContent("simTracker / AnchorToTrack")
        }
        guard let refURL = referenceObjectURL() else {
            throw HandReplayError.missingReferenceObject
        }

        statusMessage = "Loading LPVT-Simulator.referenceobject..."
        let referenceObject = try await ReferenceObject(from: refURL)
        let objectProvider = ObjectTrackingProvider(referenceObjects: [referenceObject])
        let worldProvider = WorldTrackingProvider()
        let session = ARKitSession()
        self.session = session

        statusMessage = "Looking for LPVT manikin..."
        try await session.run([objectProvider, worldProvider])
        isTracking = true

        updateTask?.cancel()
        updateTask = Task { @MainActor in
            for await update in objectProvider.anchorUpdates {
                guard !Task.isCancelled else { break }
                handleObjectAnchor(update.anchor)
            }
        }
        #endif
    }

    func lockCurrentReference() throws {
        guard let latestReference else {
            throw HandReplayError.noManikinAnchorToLock
        }

        let locked = ManikinReferenceRuntime(
            isLocked: true,
            sourceReferenceObject: latestReference.sourceReferenceObject,
            coordinateFrame: latestReference.coordinateFrame,
            worldFromObject: latestReference.worldFromObject,
            worldFromAnchorToTrack: latestReference.worldFromAnchorToTrack,
            worldFromLandmark: latestReference.worldFromLandmark
        )
        lockedReference = locked
        manikinEntity?.setTransformMatrix(locked.worldFromObject, relativeTo: nil)
        manikinEntity?.isEnabled = true
        statusMessage = "Locked manikin anchor to AnchorToTrack."
    }

    func stopTracking() {
        updateTask?.cancel()
        updateTask = nil
        session?.stop()
        session = nil
        isTracking = false
    }

    private func handleObjectAnchor(_ objectAnchor: ObjectAnchor) {
        guard objectAnchor.isTracked,
              let manikinEntity,
              let anchorToTrackEntity
        else {
            statusMessage = lockedReference == nil
                ? "Manikin tracking lost. Move the device until LPVT simulator is visible."
                : "Manikin tracking lost. Continuing with locked anchor."
            return
        }

        let worldFromObject = objectAnchor.originFromAnchorTransform
        if lockedReference == nil {
            manikinEntity.setTransformMatrix(worldFromObject, relativeTo: nil)
            manikinEntity.isEnabled = true
        }

        let worldFromAnchorToTrack = worldFromObject * anchorToTrackEntity.transformMatrix(relativeTo: manikinEntity)
        let worldFromLandmark = landmarkEntity.map { worldFromObject * $0.transformMatrix(relativeTo: manikinEntity) }
        latestReference = ManikinReferenceRuntime(
            isLocked: false,
            sourceReferenceObject: "LPVT-Simulator.referenceobject",
            coordinateFrame: "AnchorToTrack",
            worldFromObject: worldFromObject,
            worldFromAnchorToTrack: worldFromAnchorToTrack,
            worldFromLandmark: worldFromLandmark
        )

        if lockedReference == nil {
            statusMessage = "Manikin found. Lock anchor before recording."
        }
    }

    private func referenceObjectURL() -> URL? {
        realityKitContentBundle.url(
            forResource: "LPVT-Simulator",
            withExtension: "referenceobject",
            subdirectory: "ReferenceObjects"
        )
        ?? realityKitContentBundle.url(forResource: "LPVT-Simulator", withExtension: "referenceobject")
        ?? realityKitContentBundle.urls(forResourcesWithExtension: "referenceobject", subdirectory: "ReferenceObjects")?.first
        ?? realityKitContentBundle.urls(forResourcesWithExtension: "referenceobject", subdirectory: nil)?.first
    }
}
