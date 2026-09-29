import RealityKit
import SwiftUI
import UIKit

/// 충돌 그룹. 레이캐스트로 그림자 거리를 잴 때 콜슨 자신은 제외하고 LiDAR 메시만 맞히기 위해 사용한다.
enum CollisionGroups {
    static let coulson = CollisionGroup(rawValue: 1 << 1)
    static let worldMesh = CollisionGroup(rawValue: 1 << 2)
}

extension MoodColor {
    var uiColor: UIColor {
        UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

/// 자비스처럼 호출할 수 있는 '콜슨AI' 엔티티.
///
/// Siri 오브를 닮은 다층 구조: 발광 코어 → 안쪽 헤일로 → 서로 다른 축으로 회전하는 반투명 빛 띠 4개 →
/// 가산 합성 파티클 오라 → 유리 셸 → 주변을 물들이는 포인트 라이트.
/// 상태(대기·듣기·생각·말하기)에 따라 회전 속도와 맥동이 부드럽게 보간되고, 색이 바뀌면 1초간 전이된다.
/// 메시 7개 + 파티클 30여 개 수준으로 기기 부하를 낮게 유지한다.
@MainActor
final class CoulsonEntity {

    /// 콜슨의 현재 상태. 비주얼의 에너지 레벨을 결정한다.
    enum Presence {
        case idle
        case listening
        case thinking
        case speaking

        var targetEnergy: Float {
            switch self {
            case .idle: return 0.22
            case .listening: return 0.55
            case .thinking: return 1.0
            case .speaking: return 0.75
            }
        }
    }

    private struct Band {
        let pivot: Entity
        let spin: Entity
        let model: ModelEntity
        let tiltAxis: SIMD3<Float>
        let baseTilt: Float
        let spinSpeed: Float
        let hueShift: CGFloat
        let alpha: CGFloat
    }

    let root = Entity()
    static let coreRadius: Float = 0.06

    private let core: ModelEntity
    private let halo: ModelEntity
    /// 띠·오라보다 나중에 생성해야 한다. RealityKit은 같은 중심의 반투명 객체를 생성 순서로 그리므로,
    /// 셸이 먼저 만들어지면 안쪽 반투명 띠가 셸 뒤로 깊이 판정되어 보이지 않는다.
    private var shell = ModelEntity()
    private var bands: [Band] = []
    private let aura = Entity()
    private let light = Entity()

    /// 위아래로 살짝 떠 있는 애니메이션의 기준 위치. 컨트롤 창(정면 약 1.5m)과 겹치지 않도록 오른쪽 앞에 둔다.
    private(set) var basePosition: SIMD3<Float> = [0.65, 1.25, -1.1]
    private var targetBase: SIMD3<Float> = [0.65, 1.25, -1.1]

    var presence: Presence = .idle
    var isDragging = false

    private var elapsed: TimeInterval = 0
    private var energy: Float = 0.22
    private var appliedEnergy: Float = -1
    private var summonPulse: Float = 0

    // 색 전이
    private var fromAccent: UIColor = SceneMood.default.accent.uiColor
    private var toAccent: UIColor = SceneMood.default.accent.uiColor
    private var colorProgress: Float = 1

    init() {
        core = ModelEntity(mesh: .generateSphere(radius: Self.coreRadius), materials: [PhysicallyBasedMaterial()])
        core.name = "Core"
        halo = ModelEntity(mesh: .generateSphere(radius: Self.coreRadius * 1.28), materials: [UnlitMaterial()])
        halo.name = "Halo"

        root.name = "CoulsonAI"
        root.position = basePosition
        root.addChild(core)
        root.addChild(halo)

        buildBands()
        buildAura()
        buildLight()

        // 유리 셸은 반드시 마지막에 생성·추가한다 (위 `shell` 주석 참고).
        shell = ModelEntity(mesh: .generateSphere(radius: Self.coreRadius * 2.3), materials: [PhysicallyBasedMaterial()])
        shell.name = "Shell"
        root.addChild(shell)

        // 손으로 잡고 옮길 수 있도록 입력 타깃 + 충돌 형상. 시선을 두면 살짝 강조된다.
        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: Self.coreRadius * 2.6)],
            filter: CollisionFilter(group: CollisionGroups.coulson, mask: .all)
        ))
        root.components.set(HoverEffectComponent())

        // 시스템 그라운딩 그림자(LiDAR 메시를 쓸 수 없을 때의 대안).
        setGroundingShadow(true)

        applyColors(toAccent)
    }

    // MARK: - 구성

    private func buildBands() {
        let ring = Self.makeRing(radius: Self.coreRadius * 1.75, width: Self.coreRadius * 0.3, depth: Self.coreRadius * 0.05)
        let specs: [(axis: SIMD3<Float>, tilt: Float, speed: Float, hue: CGFloat, alpha: CGFloat)] = [
            ([1, 0, 0], 0.35, 0.9, 0.0, 0.7),
            ([1, 0, 0.6], 1.15, -0.7, 0.06, 0.58),
            ([0.2, 0, 1], 1.9, 1.15, -0.1, 0.5),
            ([1, 0, -0.8], 0.8, -0.5, 0.0, 0.42),
        ]
        for spec in specs {
            let pivot = Entity()
            let spin = Entity()
            let model = ModelEntity(mesh: ring, materials: [UnlitMaterial()])
            model.name = "Band"
            // 압출은 Z 방향으로 이뤄지므로, 링이 XZ 평면에 눕도록 돌린다.
            model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            spin.addChild(model)
            pivot.addChild(spin)
            root.addChild(pivot)
            bands.append(Band(
                pivot: pivot, spin: spin, model: model,
                tiltAxis: simd_normalize(spec.axis), baseTilt: spec.tilt,
                spinSpeed: spec.speed, hueShift: spec.hue, alpha: spec.alpha
            ))
        }
    }

    private func buildAura() {
        aura.name = "Aura"
        root.addChild(aura)
        Task { await refreshAura(force: true) }
    }

    private func buildLight() {
        light.name = "Glow"
        root.addChild(light)
        light.components.set(PointLightComponent(color: toAccent, intensity: 90, attenuationRadius: 1.3))
        // 현실 공간(패스스루)의 실제 표면에도 빛이 은은하게 번지도록 한다. 반경이 작아 비용이 낮다.
        light.components.set(PointLightComponent.SurroundingsLight())
    }

    /// 파티클 오라. 상태(에너지)가 눈에 띄게 바뀔 때만 다시 설정한다.
    private func refreshAura(force: Bool = false) async {
        guard force || abs(energy - appliedEnergy) > 0.12 else { return }
        appliedEnergy = energy
        let accent = currentAccent()

        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = SIMD3(repeating: Self.coreRadius * 1.9)
        emitter.birthLocation = .surface
        emitter.birthDirection = .normal
        emitter.speed = 0.03 + energy * 0.12
        emitter.speedVariation = 0.02

        var main = emitter.mainEmitter
        main.image = await ParticleFactory.shared.texture(for: .glowDot)
        main.birthRate = 18 + energy * 34
        main.lifeSpan = 1.5
        main.lifeSpanVariation = 0.4
        main.size = Self.coreRadius * 0.12 * ParticleFactory.metersToParticleSize
        main.sizeVariation = Self.coreRadius * 0.04 * ParticleFactory.metersToParticleSize
        main.sizeMultiplierAtEndOfLifespan = 1.5
        main.blendMode = .additive
        main.opacityCurve = .gradualFadeInOut
        main.isLightingEnabled = false
        main.noiseStrength = 0.06 + energy * 0.08
        main.noiseScale = 1.2
        main.color = .evolving(
            start: .single(accent.blended(with: .white, fraction: 0.35).withAlphaComponent(0.35)),
            end: .single(accent.withAlphaComponent(0))
        )
        emitter.mainEmitter = main
        aura.components.set(emitter)
    }

    // MARK: - 색

    /// 장면 분위기에 맞춰 오브의 발광 색을 바꾼다. 약 1초간 부드럽게 전이된다.
    func applyAccent(_ accent: MoodColor) {
        fromAccent = currentAccent()
        toAccent = accent.uiColor
        colorProgress = 0
    }

    private func currentAccent() -> UIColor {
        fromAccent.blended(with: toAccent, fraction: CGFloat(Self.easeInOut(colorProgress)))
    }

    private func applyColors(_ accent: UIColor) {
        var coreMaterial = PhysicallyBasedMaterial()
        coreMaterial.baseColor = .init(tint: accent)
        coreMaterial.emissiveColor = .init(color: accent)
        coreMaterial.emissiveIntensity = 3.2 + energy * 2.5
        coreMaterial.roughness = 0.25
        coreMaterial.metallic = 0.0
        core.model?.materials = [coreMaterial]

        var haloMaterial = UnlitMaterial(color: accent.blended(with: .white, fraction: 0.3))
        haloMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.22 + energy * 0.12))
        halo.model?.materials = [haloMaterial]

        var shellMaterial = PhysicallyBasedMaterial()
        shellMaterial.baseColor = .init(tint: accent.blended(with: .white, fraction: 0.75))
        shellMaterial.roughness = 0.03
        shellMaterial.metallic = 0.0
        shellMaterial.clearcoat = 1.0
        shellMaterial.clearcoatRoughness = 0.05
        shellMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.1))
        shell.model?.materials = [shellMaterial]

        for (index, band) in bands.enumerated() {
            // 마지막 띠는 흰빛에 가깝게, 나머지는 강조색 주변의 색상환에서 고른다.
            let bandColor = index == bands.count - 1
                ? accent.blended(with: .white, fraction: 0.7)
                : accent.shiftingHue(by: band.hueShift).blended(with: .white, fraction: 0.25)
            var material = UnlitMaterial(color: bandColor)
            material.blending = .transparent(opacity: .init(floatLiteral: Float(band.alpha)))
            band.model.model?.materials = [material]
        }

        light.components.set(PointLightComponent(color: accent, intensity: 70 + energy * 110, attenuationRadius: 1.3))
    }

    /// 시스템 그라운딩 그림자를 켜거나 끈다. LiDAR 거리 기반 그림자가 활성화되면 끈다.
    func setGroundingShadow(_ enabled: Bool) {
        core.components.set(GroundingShadowComponent(castsShadow: enabled))
    }

    // MARK: - 이동

    /// 호출: 지정한 위치로 부드럽게 이동하며 한 번 크게 맥동한다.
    func summon(to position: SIMD3<Float>) {
        targetBase = position
        summonPulse = 1
    }

    /// 드래그 중에는 즉시 위치를 따라간다.
    func setBaseFromDrag(_ position: SIMD3<Float>) {
        basePosition = position
        targetBase = position
    }

    // MARK: - 프레임 갱신

    /// 매 프레임 호출. 부유·맥동·띠 회전·색 전이를 갱신한다.
    func update(deltaTime: TimeInterval) {
        elapsed += deltaTime
        let dt = Float(deltaTime)
        let t = Float(elapsed)

        // 상태 에너지는 급변하지 않고 부드럽게 따라간다.
        let energySmoothing = min(1, dt * 2.5)
        energy += (presence.targetEnergy - energy) * energySmoothing
        summonPulse = max(0, summonPulse - dt * 1.4)

        // 위치: 기준점을 향해 이징 + 부유 + 미세한 유기적 드리프트.
        if !isDragging {
            let smoothing = min(1, dt * 3.5)
            basePosition += (targetBase - basePosition) * smoothing
        }
        let bob = isDragging ? 0 : sin(t * 1.4) * (0.014 + energy * 0.01)
        let driftX = isDragging ? 0 : (sin(t * 0.63) + sin(t * 1.37) * 0.5) * 0.0035
        let driftZ = isDragging ? 0 : (cos(t * 0.51) + sin(t * 1.11) * 0.5) * 0.0035
        root.position = basePosition + [driftX, bob, driftZ]

        // 코어·헤일로 맥동. 말할 때는 말소리 리듬처럼 빠르게, 생각할 때는 잦은 미세 진동.
        let breath = sin(t * 2.1) * 0.03
        let speakPulse = presence == .speaking ? abs(sin(t * 9.0) * sin(t * 2.3)) * 0.09 : 0
        let thinkJitter = presence == .thinking ? sin(t * 7.3) * 0.05 : 0
        let coreScale = 1 + breath + speakPulse + thinkJitter + summonPulse * 0.45
        core.scale = SIMD3(repeating: coreScale)
        halo.scale = SIMD3(repeating: 1 + sin(t * 1.3 + 1) * 0.08 + energy * 0.12 + summonPulse * 0.6)
        shell.scale = SIMD3(repeating: 1 + breath * 0.3 + summonPulse * 0.25)

        // 빛 띠: 각기 다른 축으로 회전하며 기울기가 천천히 흔들리고, 살짝 눌린 타원으로 변형되어 유체처럼 보인다.
        let spinBoost = 0.55 + energy * 2.4
        for (index, band) in bands.enumerated() {
            let phase = Float(index) * 1.7
            let wobble = sin(t * 0.37 + phase) * (0.25 + energy * 0.35)
            band.pivot.orientation = simd_quatf(angle: band.baseTilt + wobble, axis: band.tiltAxis)
            band.spin.orientation = simd_quatf(angle: t * band.spinSpeed * spinBoost + phase, axis: [0, 1, 0])
            let squash = sin(t * 1.7 + phase) * (0.05 + energy * 0.06)
            let grow = 1 + energy * 0.14 + summonPulse * 0.35
            band.model.scale = [(1 + squash) * grow, 1, (1 - squash) * grow]
        }

        // 색 전이 중이거나 에너지가 눈에 띄게 바뀌었을 때만 머티리얼을 갱신한다.
        var needsColorUpdate = false
        if colorProgress < 1 {
            colorProgress = min(1, colorProgress + dt / 0.9)
            needsColorUpdate = true
        }
        if abs(energy - appliedEnergy) > 0.12 {
            needsColorUpdate = true
            Task { await refreshAura() }
        }
        if needsColorUpdate {
            applyColors(currentAccent())
        }
    }

    // MARK: - 도우미

    private static func easeInOut(_ x: Float) -> Float {
        let clamped = max(0, min(1, x))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// 얇은 평면 링 메시. 2D 경로(바깥 원 + 안쪽 원, even-odd)를 얕게 압출해 만든다.
    /// RealityKit이 직접 생성하는 메시이므로 반투명 머티리얼과 안전하게 어울린다.
    private static func makeRing(radius: Float, width: Float, depth: Float) -> MeshResource {
        let outer = CGFloat(radius + width / 2)
        let inner = CGFloat(radius - width / 2)
        var path = Path()
        path.addEllipse(in: CGRect(x: -outer, y: -outer, width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))

        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: depth)
        options.chamferRadius = 0
        do {
            return try MeshResource(extruding: path, extrusionOptions: options)
        } catch {
            print("[CoulsonEntity] ring extrusion failed: \(error)")
            return .generateSphere(radius: width)
        }
    }
}

extension UIColor {
    /// 두 색을 선형 보간한다. fraction이 1이면 other 색이 된다.
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, fraction))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }

    /// 색상환에서 hue를 이동시킨다 (0~1 단위, 음수 가능).
    func shiftingHue(by delta: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        var hue = (h + delta).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return UIColor(hue: hue, saturation: min(1, s * 0.95 + 0.05), brightness: min(1, b * 0.9 + 0.1), alpha: a)
    }
}
