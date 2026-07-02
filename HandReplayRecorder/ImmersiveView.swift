import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "HandReplayRecorderRoot"
            content.add(root)
            await appModel.configureReality(root: root)
        }
    }
}
