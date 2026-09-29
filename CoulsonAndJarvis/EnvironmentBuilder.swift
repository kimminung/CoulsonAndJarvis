import RealityKit
import UIKit

/// AI가 만든 `SceneMood`를 실제 배경으로 바꾸는 빌더.
/// 스카이돔(안쪽을 바라보는 큰 구) + 지면 + 키워드 기반 입자 레이어(최대 3개)로 구성되며,
/// 무거운 이미지 생성 대신 CoreGraphics 그라디언트 텍스처와 파라메트릭 파티클만 사용한다.
@MainActor
final class EnvironmentScene {
    let root = Entity()

    private let skyDome: ModelEntity
    private let ground: ModelEntity
    private let particleRoot = Entity()
    private var particleEntities: [Entity] = []
    private var applyGeneration = 0

    init() {
        root.name = "Environment"

        var initialSky = UnlitMaterial(color: .black)
        initialSky.faceCulling = .front
        skyDome = ModelEntity(mesh: .generateSphere(radius: 60), materials: [initialSky])
        skyDome.name = "SkyDome"

        var groundMaterial = PhysicallyBasedMaterial()
        groundMaterial.baseColor = .init(tint: .darkGray)
        groundMaterial.roughness = 1.0
        ground = ModelEntity(mesh: .generatePlane(width: 120, depth: 120), materials: [groundMaterial])
        ground.name = "Ground"
        // 이머시브 공간의 원점은 사용자의 발밑 바닥이므로 지면을 y = 0 에 둔다.
        ground.position = [0, -0.005, 0]

        particleRoot.name = "Particles"

        root.addChild(skyDome)
        root.addChild(ground)
        root.addChild(particleRoot)
    }

    /// 장면 명세를 적용한다. 텍스처 생성은 비동기이므로 await 한다.
    func apply(_ mood: SceneMood) async {
        applyGeneration += 1
        let generation = applyGeneration

        if let image = SkyTextureGenerator.makeSkyImage(for: mood),
           let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) {
            guard generation == applyGeneration else { return }
            var skyMaterial = UnlitMaterial()
            skyMaterial.color = .init(tint: .white, texture: .init(texture))
            skyMaterial.faceCulling = .front
            skyDome.model?.materials = [skyMaterial]
        }

        var groundMaterial = PhysicallyBasedMaterial()
        groundMaterial.baseColor = .init(tint: mood.ground.uiColor)
        groundMaterial.roughness = 1.0
        groundMaterial.metallic = 0.0
        ground.model?.materials = [groundMaterial]

        let placements = await ParticleFactory.shared.makePlacements(for: mood.particles)
        guard generation == applyGeneration else { return }
        applyParticles(placements)
    }

    // MARK: - 입자 레이어

    private func applyParticles(_ placements: [ParticleFactory.Placement]) {
        // 필요한 개수만큼 이미터 엔티티를 맞춘다.
        while particleEntities.count < placements.count {
            let entity = Entity()
            entity.name = "ParticleLayer\(particleEntities.count)"
            particleRoot.addChild(entity)
            particleEntities.append(entity)
        }
        while particleEntities.count > placements.count {
            particleEntities.removeLast().removeFromParent()
        }
        for (entity, placement) in zip(particleEntities, placements) {
            entity.position = placement.position
            entity.components.set(placement.emitter)
        }
    }
}
