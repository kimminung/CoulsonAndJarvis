import ARKit
import QuartzCore
import RealityKit
import UIKit

/// ARKit 데이터 제공자를 관리한다.
/// - `SceneReconstructionProvider`: Vision Pro의 LiDAR 기반 공간 메시. 접근 가능하면 충돌 전용 엔티티로 만들어
///   콜슨AI 아래 표면까지의 거리를 레이캐스트로 잰다. (시뮬레이터에서는 지원되지 않아 자동으로 비활성화된다.)
/// - `WorldTrackingProvider`: 헤드 포즈. "콜슨" 호출 시 사용자 앞으로 데려오는 데 사용한다.
@Observable
@MainActor
final class SpatialSensing {

    enum LidarState: Equatable {
        case unavailable(String)
        case authorizing
        case running(meshCount: Int)

        var label: String {
            switch self {
            case .unavailable(let reason): return "LiDAR 메시 사용 불가 · \(reason)"
            case .authorizing: return "공간 인식 권한 요청 중"
            case .running(let count): return "LiDAR 메시 추적 중 · \(count)개 조각"
            }
        }

        var isRunningWithMesh: Bool {
            if case .running(let count) = self { return count > 0 }
            return false
        }
    }

    private(set) var lidarState: LidarState = .unavailable("미확인")
    private(set) var isWorldTrackingRunning = false

    /// LiDAR 메시로 만든 충돌 전용 엔티티들의 부모. 렌더링되지 않는다.
    let meshRoot = Entity()

    private let session = ARKitSession()
    private var sceneReconstruction: SceneReconstructionProvider?
    private var worldTracking: WorldTrackingProvider?
    private var meshEntities: [UUID: Entity] = [:]
    private var runTask: Task<Void, Never>?

    init() {
        meshRoot.name = "LiDARMesh"
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { await run() }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        session.stop()
        isWorldTrackingRunning = false
        for entity in meshEntities.values {
            entity.removeFromParent()
        }
        meshEntities.removeAll()
    }

    // MARK: - 세션

    private func run() async {
        var providers: [any DataProvider] = []

        if WorldTrackingProvider.isSupported {
            let provider = WorldTrackingProvider()
            worldTracking = provider
            providers.append(provider)
        }

        if SceneReconstructionProvider.isSupported {
            let provider = SceneReconstructionProvider()
            sceneReconstruction = provider
            providers.append(provider)
            lidarState = .authorizing
        } else {
            lidarState = .unavailable("이 기기 또는 시뮬레이터는 공간 메시를 제공하지 않음")
        }

        guard !providers.isEmpty else { return }

        do {
            try await session.run(providers)
        } catch {
            lidarState = .unavailable(error.localizedDescription)
            return
        }

        isWorldTrackingRunning = worldTracking != nil

        guard let sceneReconstruction else { return }
        lidarState = .running(meshCount: 0)

        for await update in sceneReconstruction.anchorUpdates {
            if Task.isCancelled { break }
            await handle(update)
        }
    }

    private func handle(_ update: AnchorUpdate<MeshAnchor>) async {
        let anchor = update.anchor
        switch update.event {
        case .added, .updated:
            // 메시를 물리 엔진용 충돌 형상으로 변환한다. 시간이 걸릴 수 있어 비동기.
            guard let shape = try? await ShapeResource.generateStaticMesh(from: anchor) else { return }
            let entity: Entity
            if let existing = meshEntities[anchor.id] {
                entity = existing
            } else {
                entity = Entity()
                entity.name = "Mesh-\(anchor.id.uuidString.prefix(6))"
                meshRoot.addChild(entity)
                meshEntities[anchor.id] = entity
            }
            entity.setTransformMatrix(anchor.originFromAnchorTransform, relativeTo: nil)
            entity.components.set(CollisionComponent(
                shapes: [shape],
                isStatic: true,
                filter: CollisionFilter(group: CollisionGroups.worldMesh, mask: [])
            ))
        case .removed:
            meshEntities[anchor.id]?.removeFromParent()
            meshEntities.removeValue(forKey: anchor.id)
        }
        lidarState = .running(meshCount: meshEntities.count)
    }

    // MARK: - 헤드 포즈

    /// 현재 기기(머리)의 위치와 정면 방향. 추적 중이 아니면 nil.
    func devicePose() -> (position: SIMD3<Float>, forward: SIMD3<Float>)? {
        guard let worldTracking, worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        let matrix = anchor.originFromAnchorTransform
        let position = SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        // 카메라 좌표계에서 -Z 가 정면이다.
        let forward = -SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        return (position, simd_normalize(forward))
    }
}

/// LiDAR 메시까지의 거리에 따라 크기와 진하기가 변하는 부드러운 원형 그림자.
/// 실제 그림자처럼 표면이 멀어질수록 넓고 흐려진다.
@MainActor
final class DistanceShadow {
    let root = Entity()

    private let disc: ModelEntity
    private var opacityTexture: TextureResource?
    private var lastOpacity: Float = -1
    private let baseDiameter: Float = CoulsonEntity.coreRadius * 2.4

    init() {
        var material = UnlitMaterial(color: .black)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.4))
        disc = ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [material])
        disc.name = "DistanceShadow"
        disc.scale = [baseDiameter, 1, baseDiameter]
        root.addChild(disc)
        root.isEnabled = false

        Task { await loadMask() }
    }

    private func loadMask() async {
        guard let image = SkyTextureGenerator.makeShadowMask(),
              let texture = try? await TextureResource(image: image, options: .init(semantic: .raw)) else { return }
        opacityTexture = texture
        lastOpacity = -1
    }

    private func applyOpacity(_ value: Float) {
        guard abs(value - lastOpacity) > 0.02 else { return }
        lastOpacity = value
        var material = UnlitMaterial(color: .black)
        if let opacityTexture {
            material.blending = .transparent(opacity: .init(scale: value, texture: .init(opacityTexture)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: value))
        }
        disc.model?.materials = [material]
    }

    /// 레이캐스트 결과로 그림자를 표면 위에 놓는다.
    func update(hitPosition: SIMD3<Float>, normal: SIMD3<Float>, distance: Float) {
        root.isEnabled = true
        let n = simd_normalize(normal)
        root.position = hitPosition + n * 0.006

        let up: SIMD3<Float> = [0, 1, 0]
        if simd_dot(up, n) < 0.9995 {
            root.orientation = simd_quatf(from: up, to: n)
        } else {
            root.orientation = simd_quatf(angle: 0, axis: up)
        }

        let spread = baseDiameter * (1 + distance * 0.5)
        disc.scale = [spread, 1, spread]
        applyOpacity(max(0.08, 0.62 - distance * 0.22))
    }

    func hide() {
        root.isEnabled = false
    }
}
