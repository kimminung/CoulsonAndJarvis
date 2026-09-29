import CoreGraphics
import RealityKit
import UIKit

/// `ParticleLayer` 명세를 실제 `ParticleEmitterComponent`로 조립한다.
/// 모양 스프라이트는 CoreGraphics로 한 번만 그려 캐시하므로 어떤 키워드가 와도 추가 에셋이 필요 없다.
@MainActor
final class ParticleFactory {
    static let shared = ParticleFactory()

    /// 전체 레이어의 초당 생성 수 합계 상한. 기기 과부하를 막는다.
    static let maximumTotalBirthRate: Float = 1400

    /// `ParticleEmitter.size`는 미터가 아니다. 시뮬레이터 측정 결과 1 단위가 약 2.5m 로 보이므로,
    /// 명세의 미터 단위 크기에 이 계수를 곱해 파티클 크기로 바꾼다.
    static let metersToParticleSize: Float = 0.4

    private var textureCache: [ParticleShape: TextureResource] = [:]

    private init() {}

    // MARK: - 텍스처

    func texture(for shape: ParticleShape) async -> TextureResource? {
        if let cached = textureCache[shape] { return cached }
        guard let image = Self.drawSprite(shape, size: 128),
              let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else {
            return nil
        }
        textureCache[shape] = texture
        return texture
    }

    // MARK: - 이미터 조립

    struct Placement {
        var emitter: ParticleEmitterComponent
        var position: SIMD3<Float>
    }

    /// 레이어 배열을 이미터로 바꾼다. 합계 생성 수가 상한을 넘으면 비율대로 줄인다.
    func makePlacements(for layers: [ParticleLayer]) async -> [Placement] {
        var placements: [Placement] = []
        for layer in layers.prefix(3) {
            placements.append(await makePlacement(for: layer))
        }
        let total = placements.reduce(Float(0)) { $0 + $1.emitter.mainEmitter.birthRate }
        if total > Self.maximumTotalBirthRate {
            let scale = Self.maximumTotalBirthRate / total
            for index in placements.indices {
                placements[index].emitter.mainEmitter.birthRate *= scale
            }
        }
        return placements
    }

    private func makePlacement(for layer: ParticleLayer) async -> Placement {
        let size = Float(max(0.005, min(0.5, layer.size)))
        let density = Float(max(0.05, min(1, layer.density)))
        let speed = Float(max(0.05, min(1, layer.speed)))
        let color = layer.color.uiColor

        var emitter = ParticleEmitterComponent()
        var main = emitter.mainEmitter
        main.image = await texture(for: layer.shape)
        main.size = size * Self.metersToParticleSize
        main.sizeVariation = size * Self.metersToParticleSize * 0.35
        main.isLightingEnabled = false
        main.opacityCurve = .gradualFadeInOut
        main.blendMode = layer.glows ? .additive : .alpha

        // 색: 약간의 밝기 변주로 단조로움을 피한다. 빛나는 입자는 수명 끝에 투명해진다.
        let lighter = color.blended(with: .white, fraction: 0.25)
        if layer.glows {
            main.color = .evolving(start: .random(a: color, b: lighter), end: .single(color.withAlphaComponent(0)))
        } else {
            main.color = .constant(.random(a: color, b: lighter))
        }

        // 모양별 회전·늘어남.
        switch layer.shape {
        case .petal, .feather, .flake:
            main.angle = 0
            main.angleVariation = .pi
            main.angularSpeed = 1.6 * speed + 0.4
            main.angularSpeedVariation = 1.2
        case .streak:
            main.stretchFactor = 2.5 + speed * 2
        default:
            break
        }

        // 작은 입자는 많이, 큰 입자는 적게 생성해야 밀도가 비슷하게 보인다.
        let sizeFactor = max(0.25, min(3.0, 0.02 / size))
        var position: SIMD3<Float> = [0, 1.6, 0]

        switch layer.motion {
        case .fall:
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [9, 0.3, 9]
            emitter.birthLocation = .volume
            emitter.birthDirection = .world
            emitter.emissionDirection = [0, -1, 0]
            emitter.speed = 0.3 + speed * 3.2
            emitter.speedVariation = 0.2
            main.spreadingAngle = 0.12
            main.lifeSpan = Double(5.0 / max(0.4, emitter.speed)) + 0.8
            main.lifeSpanVariation = 0.6
            main.acceleration = [0, -0.25 * speed, 0]
            main.noiseStrength = layer.shape == .streak ? 0.02 : 0.25 + (1 - speed) * 0.3
            main.noiseScale = 0.8
            main.noiseAnimationSpeed = 0.4
            main.birthRate = 260 * density * sizeFactor
            position = [0, 4.2, 0]

        case .rise:
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [8, 0.4, 8]
            emitter.birthLocation = .volume
            emitter.birthDirection = .world
            emitter.emissionDirection = [0, 1, 0]
            emitter.speed = 0.15 + speed * 1.2
            emitter.speedVariation = 0.15
            main.spreadingAngle = 0.35
            main.lifeSpan = 4.5
            main.lifeSpanVariation = 1.5
            main.acceleration = [0, 0.05 * speed, 0]
            main.noiseStrength = 0.2 + speed * 0.2
            main.noiseScale = 0.7
            main.noiseAnimationSpeed = 0.5
            main.birthRate = 90 * density * sizeFactor
            position = [0, 0.15, 0]

        case .drift:
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [8, 3.0, 8]
            emitter.birthLocation = .volume
            emitter.birthDirection = .world
            emitter.emissionDirection = [0, 1, 0]
            main.spreadingAngle = .pi
            emitter.speed = 0.02 + speed * 0.18
            emitter.speedVariation = 0.05
            main.lifeSpan = 9
            main.lifeSpanVariation = 3
            main.dampingFactor = 0.4
            main.noiseStrength = 0.2 + speed * 0.5
            main.noiseScale = 0.6
            main.noiseAnimationSpeed = 0.3 + speed * 0.4
            main.birthRate = 40 * density * sizeFactor
            position = [0, 1.7, 0]

        case .swirl:
            emitter.emitterShape = .cylinder
            emitter.emitterShapeSize = [4.5, 3.0, 4.5]
            emitter.birthLocation = .volume
            emitter.birthDirection = .world
            emitter.emissionDirection = [0, 1, 0]
            main.spreadingAngle = .pi
            emitter.speed = 0.1 + speed * 0.3
            main.lifeSpan = 7
            main.lifeSpanVariation = 2
            main.vortexDirection = [0, 1, 0]
            main.vortexStrength = 1.5 + speed * 4
            main.noiseStrength = 0.15
            main.noiseScale = 0.7
            main.dampingFactor = 0.2
            main.birthRate = 60 * density * sizeFactor
            position = [0, 1.6, 0]

        case .burst:
            emitter.emitterShape = .sphere
            emitter.emitterShapeSize = [0.25, 0.25, 0.25]
            emitter.birthLocation = .surface
            emitter.birthDirection = .normal
            emitter.speed = 1.5 + speed * 3.5
            emitter.speedVariation = 0.6
            main.spreadingAngle = 0.3
            main.lifeSpan = 1.6
            main.lifeSpanVariation = 0.5
            main.acceleration = [0, -2.2, 0]
            main.dampingFactor = 1.2
            main.sizeMultiplierAtEndOfLifespan = 0.3
            // 지속적으로 터져 나오는 불꽃 분수. 주기적 폭발 대신 연속 방출로 단순하게 유지한다.
            main.birthRate = 260 * density
            position = [0, 3.2, -4.0]
        }

        emitter.mainEmitter = main
        return Placement(emitter: emitter, position: position)
    }

    // MARK: - 스프라이트 그리기

    /// 흰색 + 알파로 모양을 그린다. 실제 색은 파티클 색으로 곱해진다.
    static func drawSprite(_ shape: ParticleShape, size: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let s = CGFloat(size)
        let center = CGPoint(x: s / 2, y: s / 2)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
        func radial(_ stops: [(CGFloat, CGFloat)], radius: CGFloat) {
            let colors = stops.map { white($0.1) } as CFArray
            let locations = stops.map(\.0)
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: radius, options: [])
            }
        }

        switch shape {
        case .glowDot:
            radial([(0, 1.0), (0.35, 0.75), (1.0, 0.0)], radius: s * 0.5)

        case .spark:
            radial([(0, 1.0), (0.18, 0.9), (0.45, 0.25), (1.0, 0.0)], radius: s * 0.5)

        case .petal:
            // 꽃잎: 한쪽이 뾰족한 물방울꼴.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: s * 0.5, y: s * 0.06))
            path.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.94),
                          control1: CGPoint(x: s * 0.98, y: s * 0.35), control2: CGPoint(x: s * 0.9, y: s * 0.95))
            path.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.06),
                          control1: CGPoint(x: s * 0.1, y: s * 0.95), control2: CGPoint(x: s * 0.02, y: s * 0.35))
            context.addPath(path)
            context.setFillColor(white(0.95))
            context.fillPath()
            // 가운데 결
            context.setStrokeColor(white(0.35))
            context.setLineWidth(s * 0.03)
            context.move(to: CGPoint(x: s * 0.5, y: s * 0.12))
            context.addLine(to: CGPoint(x: s * 0.5, y: s * 0.86))
            context.strokePath()

        case .streak:
            // 빗줄기: 위쪽이 옅어지는 얇은 세로 선.
            let rect = CGRect(x: s * 0.44, y: s * 0.05, width: s * 0.12, height: s * 0.9)
            let path = CGPath(roundedRect: rect, cornerWidth: s * 0.06, cornerHeight: s * 0.06, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.clip()
            if let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: [white(0.0), white(0.9), white(0.9), white(0.2)] as CFArray,
                                         locations: [0, 0.35, 0.8, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s * 0.95),
                                           end: CGPoint(x: 0, y: s * 0.05), options: [])
            }
            context.restoreGState()

        case .flake:
            // 눈송이: 여섯 갈래 가지와 곁가지.
            context.setStrokeColor(white(0.95))
            context.setLineCap(.round)
            context.setLineWidth(s * 0.055)
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3
                let dir = CGPoint(x: cos(angle), y: sin(angle))
                let tip = CGPoint(x: center.x + dir.x * s * 0.44, y: center.y + dir.y * s * 0.44)
                context.move(to: center)
                context.addLine(to: tip)
                // 곁가지
                let branchBase = CGPoint(x: center.x + dir.x * s * 0.27, y: center.y + dir.y * s * 0.27)
                for side in [-1.0, 1.0] {
                    let branchAngle = angle + CGFloat(side) * .pi / 3.2
                    let end = CGPoint(x: branchBase.x + cos(branchAngle) * s * 0.13,
                                      y: branchBase.y + sin(branchAngle) * s * 0.13)
                    context.move(to: branchBase)
                    context.addLine(to: end)
                }
            }
            context.strokePath()
            radial([(0, 0.6), (1, 0)], radius: s * 0.12)

        case .bubble:
            // 비눗방울: 테두리 링 + 옅은 속 + 하이라이트.
            context.setFillColor(white(0.10))
            context.fillEllipse(in: CGRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84))
            context.setStrokeColor(white(0.85))
            context.setLineWidth(s * 0.05)
            context.strokeEllipse(in: CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8))
            context.setFillColor(white(0.9))
            context.fillEllipse(in: CGRect(x: s * 0.26, y: s * 0.62, width: s * 0.16, height: s * 0.1))

        case .star:
            // 별: 네 갈래 광선 + 중심 글로우.
            let path = CGMutablePath()
            let outer = s * 0.48, inner = s * 0.07
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4 - .pi / 2
                let radius = index.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(white(0.95))
            context.fillPath()
            radial([(0, 1.0), (0.5, 0.35), (1, 0)], radius: s * 0.3)

        case .feather:
            // 깃털·종이 조각: 길쭉하고 가장자리가 부드러운 타원.
            context.saveGState()
            context.addEllipse(in: CGRect(x: s * 0.3, y: s * 0.06, width: s * 0.4, height: s * 0.88))
            context.clip()
            if let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: [white(0.95), white(0.95), white(0.55)] as CFArray,
                                         locations: [0, 0.6, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: s * 0.3, y: 0),
                                           end: CGPoint(x: s * 0.7, y: 0), options: [])
            }
            context.restoreGState()
        }

        return context.makeImage()
    }
}
