import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(alignment: .top, spacing: 16) {
                workflowPanel(appModel)
                diagnosticsPanel(appModel)
            }

            if let url = appModel.lastExportedURL {
                HStack(spacing: 12) {
                    Label(url.lastPathComponent, systemImage: "doc.badge.arrow.up")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                    ShareLink(item: url) {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = appModel.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(28)
        .glassBackgroundEffect()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HandReplayRecorder")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Record Vision Pro hand tracking relative to the LPVT manikin, then replay or export it for the next animation pipeline step.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func workflowPanel(_ appModel: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Workflow", systemImage: "record.circle")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                Button {
                    Task {
                        appModel.immersiveSpaceState = .inTransition
                        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                        if case .opened = result {
                            appModel.immersiveSpaceState = .open
                        } else {
                            appModel.immersiveSpaceState = .closed
                        }
                    }
                } label: {
                    Label("Open Space", systemImage: "visionpro")
                }
                .disabled(appModel.immersiveSpaceState != .closed)

                Button {
                    Task {
                        appModel.stopImmersiveWork()
                        await dismissImmersiveSpace()
                        appModel.immersiveSpaceState = .closed
                    }
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
                .disabled(appModel.immersiveSpaceState == .closed)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    Task { await appModel.startFindingManikin() }
                } label: {
                    Label("Find Manikin", systemImage: "scope")
                }
                .disabled(appModel.immersiveSpaceState != .open || appModel.manikinTracker.isTracking)

                Button {
                    appModel.lockManikin()
                } label: {
                    Label("Lock Manikin Anchor", systemImage: "pin.fill")
                }
                .disabled(appModel.manikinTracker.latestReference == nil)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await appModel.startRecording() }
                } label: {
                    Label("Record", systemImage: "record.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!appModel.canRecord)

                Button {
                    appModel.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!appModel.canStop)

                Button {
                    appModel.play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!appModel.canPlay)
            }

            HStack(spacing: 10) {
                Button {
                    appModel.exportRecording()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!appModel.canExport)

                Button(role: .destructive) {
                    appModel.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(appModel.recorder.currentRecording == nil && !appModel.recorder.isRecording)
            }

            Text(appModel.recorder.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(width: 470, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func diagnosticsPanel(_ appModel: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Diagnostics", systemImage: "waveform.path.ecg")
                .font(.title2)
                .fontWeight(.semibold)

            diagnosticRow("Space", value: spaceLabel(appModel.immersiveSpaceState))
            diagnosticRow("Manikin", value: appModel.manikinTracker.statusMessage)
            diagnosticRow("Anchor", value: appModel.manikinTracker.lockedReference == nil ? "Unlocked" : "Locked to AnchorToTrack")
            diagnosticRow("Hands", value: appModel.recorder.trackedHandsSummary)
            diagnosticRow("Frames", value: "\(appModel.recorder.recordedFrameCount)")
            diagnosticRow("Duration", value: String(format: "%.2f s", appModel.recorder.recordingDuration))
            diagnosticRow("Export frame", value: appModel.recorder.currentRecording?.manikinReference.coordinateFrame ?? "none")

            Text("Precision note: playback reproduces ARKit-estimated hand data. It is not a millimeter-accurate medical motion-capture measurement.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 470, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private func spaceLabel(_ state: AppModel.ImmersiveSpaceState) -> String {
        switch state {
        case .closed: return "Closed"
        case .inTransition: return "Opening..."
        case .open: return "Open"
        }
    }
}

#Preview(windowStyle: .plain) {
    ContentView()
        .environment(AppModel())
}
