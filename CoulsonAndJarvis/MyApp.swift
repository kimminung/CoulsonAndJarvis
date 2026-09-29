import SwiftUI

@main
struct MyApp: App {
    @State private var model = AppModel()
    /// 현실 공간 모드는 `.mixed`, 몰입 배경 모드는 다이얼로 조절 가능한 `.progressive` 를 사용한다.
    @State private var immersionStyle: any ImmersionStyle = .mixed

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 560, height: 900)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(model)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .progressive)
        .upperLimbVisibility(.visible)
        .onChange(of: model.spaceMode, initial: true) {
            switch model.spaceMode {
            case .passthrough:
                immersionStyle = .mixed
            case .immersive:
                immersionStyle = .progressive(0.15...1.0, initialAmount: 0.6)
            }
        }
    }
}
