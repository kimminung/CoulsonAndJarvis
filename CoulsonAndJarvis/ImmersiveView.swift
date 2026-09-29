import RealityKit
import SwiftUI

/// 이머시브 공간의 본체. 콜슨AI, AI 배경, LiDAR 기반 그림자를 한 RealityView 안에서 운용한다.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model

    @State private var coulson = CoulsonEntity()
    @State private var environment = EnvironmentScene()
    @State private var sensing = SpatialSensing()
    @State private var shadow = DistanceShadow()

    @State private var updateSubscription: EventSubscription?
    @State private var dragOffset: SIMD3<Float>?
    @State private var lidarShadowActive = false
    @State private var lastReportedDistance: Float = -1

    private static let labelAttachmentID = "coulsonLabel"

    var body: some View {
        RealityView { content, attachments in
            content.add(environment.root)
            content.add(sensing.meshRoot)
            content.add(shadow.root)
            content.add(coulson.root)

            if let label = attachments.entity(for: Self.labelAttachmentID) {
                label.position = [0, CoulsonEntity.coreRadius * 3.3, 0]
                label.components.set(BillboardComponent())
                coulson.root.addChild(label)
            }

            environment.root.isEnabled = model.spaceMode == .immersive
            await environment.apply(model.mood)
            coulson.applyAccent(model.mood.accent)
            sensing.start()

            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                tick(deltaTime: event.deltaTime)
            }
        } attachments: {
            Attachment(id: Self.labelAttachmentID) {
                CoulsonLabelView()
            }
        }
        .gesture(dragGesture)
        .onImmersionChange { _, newContext in
            model.immersionAmount = newContext.amount ?? 0
        }
        .onChange(of: model.moodVersion) {
            let mood = model.mood
            coulson.applyAccent(mood.accent)
            Task { await environment.apply(mood) }
        }
        .onChange(of: model.spaceMode) {
            environment.root.isEnabled = model.spaceMode == .immersive
        }
        .onChange(of: model.isCoulsonSummoned) {
            if model.isCoulsonSummoned {
                summonCoulson()
            }
        }
        .onChange(of: sensing.lidarState, initial: true) {
            model.lidarStatus = sensing.lidarState.label
        }
        .onAppear {
            model.isImmersiveSpaceOpen = true
        }
        .onDisappear {
            model.isImmersiveSpaceOpen = false
            sensing.stop()
            updateSubscription = nil
        }
    }

    // MARK: - 프레임 갱신

    private func tick(deltaTime: TimeInterval) {
        coulson.presence = currentPresence()
        coulson.update(deltaTime: deltaTime)
        updateShadow()
    }

    /// 앱 상태로부터 콜슨의 표현 상태를 정한다. 우선순위: 생각 > 말하기 > 듣기 > 대기.
    private func currentPresence() -> CoulsonEntity.Presence {
        if model.director.isThinking { return .thinking }
        if Date.now < model.speakingUntil { return .speaking }
        if model.speech.state == .listening { return .listening }
        return .idle
    }

    /// 현실 공간 모드에서 LiDAR 메시로 콜슨 아래 표면까지의 거리를 재고 그림자를 놓는다.
    private func updateShadow() {
        guard model.spaceMode == .passthrough,
              sensing.lidarState.isRunningWithMesh,
              let scene = coulson.root.scene else {
            setLidarShadow(active: false)
            return
        }

        let origin = coulson.root.position(relativeTo: nil)
        let hits = scene.raycast(
            origin: origin,
            direction: [0, -1, 0],
            length: 4.0,
            query: .nearest,
            mask: CollisionGroups.worldMesh,
            relativeTo: nil
        )

        guard let hit = hits.first else {
            setLidarShadow(active: false)
            return
        }

        shadow.update(hitPosition: hit.position, normal: hit.normal, distance: hit.distance)
        setLidarShadow(active: true)

        // 2cm 이상 바뀌었을 때만 UI 상태를 갱신해 매 프레임 재렌더링을 피한다.
        if abs(hit.distance - lastReportedDistance) > 0.02 {
            lastReportedDistance = hit.distance
            model.shadowDistanceText = String(format: "%.2f m", hit.distance)
        }
    }

    private func setLidarShadow(active: Bool) {
        guard active != lidarShadowActive else {
            if !active { shadow.hide() }
            return
        }
        lidarShadowActive = active
        // LiDAR 그림자가 있을 때는 시스템 그라운딩 그림자를 꺼서 이중 그림자를 피한다.
        coulson.setGroundingShadow(!active)
        if !active {
            shadow.hide()
            lastReportedDistance = -1
            model.shadowDistanceText = nil
        }
    }

    // MARK: - 호출

    /// 사용자 머리 위치 기준 정면 약 0.9m, 눈높이보다 약간 아래로 콜슨을 부른다.
    private func summonCoulson() {
        var target: SIMD3<Float> = [0, 1.3, -0.9]
        if let pose = sensing.devicePose() {
            var forward = pose.forward
            forward.y = 0
            if simd_length(forward) > 0.001 {
                forward = simd_normalize(forward)
            } else {
                forward = [0, 0, -1]
            }
            target = pose.position + forward * 0.9 + [0, -0.12, 0]
        }
        coulson.summon(to: target)
        model.isCoulsonSummoned = false
    }

    // MARK: - 드래그로 옮기기

    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToEntity(coulson.root)
            .onChanged { value in
                let location = value.convert(value.location3D, from: .local, to: .scene)
                if dragOffset == nil {
                    dragOffset = coulson.basePosition - location
                    coulson.isDragging = true
                }
                coulson.setBaseFromDrag(location + (dragOffset ?? .zero))
            }
            .onEnded { _ in
                dragOffset = nil
                coulson.isDragging = false
            }
    }
}

/// 콜슨AI 위에 떠 있는 이름표와 말풍선.
private struct CoulsonLabelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Label("콜슨AI", systemImage: "sparkle")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
            if model.director.isThinking {
                ProgressView()
                    .controlSize(.small)
            } else if let bubble = model.coulsonBubble, !bubble.isEmpty {
                Text(bubble)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
    }
}
