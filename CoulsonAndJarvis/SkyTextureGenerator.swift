import CoreGraphics
import Foundation

/// 장면 명세로부터 스카이돔(등장방형 투영)용 텍스처와 그림자용 텍스처를 CoreGraphics로 그린다.
/// GPU를 쓰는 이미지 생성 대신, 그라디언트·별·천체 정도만 가볍게 합성한다.
enum SkyTextureGenerator {

    /// 스카이돔에 입힐 등장방형 텍스처. 폭 : 높이 = 2 : 1.
    static func makeSkyImage(for mood: SceneMood, width: Int = 2048) -> CGImage? {
        let height = width / 2
        guard let context = makeContext(width: width, height: height) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        // 1. 하늘 → 지평선 → 지면으로 이어지는 세로 그라디언트.
        //    (이미지 위쪽이 천정, 아래쪽이 발밑)
        let horizon = mood.skyHorizon.cgColor
        let fogColor = blend(horizon, with: CGColor(gray: 0.78, alpha: 1), amount: CGFloat(mood.fog) * 0.6)
        let colors: [CGColor] = [
            mood.skyTop.cgColor,          // 천정
            blend(mood.skyTop.cgColor, with: fogColor, amount: 0.45),
            fogColor,                     // 지평선
            blend(mood.ground.cgColor, with: fogColor, amount: 0.5 + CGFloat(mood.fog) * 0.3),
            mood.ground.cgColor,          // 발밑
        ]
        let locations: [CGFloat] = [1.0, 0.68, 0.5, 0.42, 0.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: colors as CFArray,
                                     locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // 2. 별. 밀도에 따라 개수를 정하고, 재현 가능한 난수를 사용한다.
        if mood.stars > 0.02 {
            var generator = SeededGenerator(seed: 0xC0_15_50)
            let count = Int(mood.stars * 1400)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0..<CGFloat(width), using: &generator)
                // 지평선(0.5) 위쪽에만 별을 뿌린다. 천정 근처일수록 촘촘하게.
                let y = CGFloat(height) * (0.52 + 0.48 * pow(CGFloat.random(in: 0..<1, using: &generator), 0.6))
                // 돔이 매우 크게 확대되므로 별은 1~2픽셀 안에서만 그려야 흐릿한 덩어리가 되지 않는다.
                let radius = CGFloat.random(in: 0.45...1.1, using: &generator)
                let alpha = CGFloat.random(in: 0.35...1.0, using: &generator) * CGFloat(1 - mood.fog * 0.6)
                context.setFillColor(CGColor(gray: 1, alpha: alpha))
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }

        // 3. 태양 또는 달. 지평선 위 약 30° 높이에 놓고 부드러운 글로우를 더한다.
        if mood.celestial != .none {
            let center = CGPoint(x: CGFloat(width) * 0.62, y: CGFloat(height) * 0.72)
            let isSun = mood.celestial == .sun
            let bodyColor = isSun ? CGColor(srgbRed: 1, green: 0.96, blue: 0.85, alpha: 1)
                                  : CGColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: 1)
            let bodyRadius = CGFloat(height) * (isSun ? 0.045 : 0.035)
            let glowRadius = bodyRadius * (isSun ? 6 : 3.5)

            if let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [bodyColor.copy(alpha: isSun ? 0.55 : 0.35)!,
                                              bodyColor.copy(alpha: 0)!] as CFArray,
                                     locations: [0, 1]) {
                context.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: glowRadius, options: [])
            }
            context.setFillColor(bodyColor)
            context.fillEllipse(in: CGRect(x: center.x - bodyRadius, y: center.y - bodyRadius,
                                           width: bodyRadius * 2, height: bodyRadius * 2))
        }

        _ = rect
        return context.makeImage()
    }

    /// 콜슨AI 그림자용 방사형 그레이스케일 텍스처(중심 흰색 → 가장자리 검정). 불투명도 맵으로 사용한다.
    static func makeShadowMask(size: Int = 256) -> CGImage? {
        guard let context = makeContext(width: size, height: size) else { return nil }
        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [CGColor(gray: 1, alpha: 1),
                                              CGColor(gray: 0.55, alpha: 1),
                                              CGColor(gray: 0, alpha: 1)] as CFArray,
                                     locations: [0, 0.45, 1]) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: CGFloat(size) / 2, options: [])
        }
        return context.makeImage()
    }

    // MARK: - 도우미

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func blend(_ a: CGColor, with b: CGColor, amount: CGFloat) -> CGColor {
        let t = max(0, min(1, amount))
        guard let ca = a.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
              let cb = b.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
              ca.count >= 3, cb.count >= 3 else { return a }
        return CGColor(
            srgbRed: ca[0] + (cb[0] - ca[0]) * t,
            green: ca[1] + (cb[1] - ca[1]) * t,
            blue: ca[2] + (cb[2] - ca[2]) * t,
            alpha: 1
        )
    }
}

/// 별 배치를 매번 같게 만들기 위한 간단한 결정적 난수 생성기 (xorshift64*).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
