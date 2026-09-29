import Foundation
import FoundationModels
import SwiftUI

// MARK: - 장면 명세 (온디바이스 모델이 생성하는 구조화된 결과)

/// 0~255 범위의 RGB 색상. 작은 온디바이스 모델이 안정적으로 생성할 수 있도록 정수로 표현한다.
@Generable(description: "0에서 255 사이의 정수 RGB 색상")
struct MoodColor: Equatable {
    @Guide(description: "빨강 채널", .range(0...255))
    var red: Int
    @Guide(description: "초록 채널", .range(0...255))
    var green: Int
    @Guide(description: "파랑 채널", .range(0...255))
    var blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        red = Int((hex >> 16) & 0xFF)
        green = Int((hex >> 8) & 0xFF)
        blue = Int(hex & 0xFF)
    }

    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

@Generable(description: "하늘에 떠 있는 천체")
enum CelestialBody: String, CaseIterable {
    case none
    case sun
    case moon
}

/// 입자 하나를 그리는 스프라이트 모양. 모델은 사용자가 말한 사물에 가장 가까운 모양을 고른다.
@Generable(description: "입자의 모양. glowDot=부드러운 빛점(반딧불·먼지·안개 뭉치), petal=꽃잎·나뭇잎, streak=빗줄기·유성처럼 세로로 긴 선, flake=눈송이, spark=불씨·불꽃, bubble=비눗방울·물방울, star=반짝이는 별, feather=깃털·종이 조각·나비처럼 길쭉하고 부드러운 조각")
enum ParticleShape: String, CaseIterable {
    case glowDot
    case petal
    case streak
    case flake
    case spark
    case bubble
    case star
    case feather
}

@Generable(description: "입자가 움직이는 방식. fall=위에서 아래로 떨어짐(비·눈·꽃잎), rise=아래에서 위로 떠오름(불씨·비눗방울), drift=공중에 떠서 천천히 떠다님(먼지·반딧불·별), swirl=소용돌이치듯 회전, burst=한 지점에서 사방으로 터짐(폭죽·불꽃)")
enum ParticleMotion: String, CaseIterable {
    case fall
    case rise
    case drift
    case swirl
    case burst
}

/// 배경을 채우는 입자 레이어 하나. 모델이 사용자의 키워드를 그대로 반영해 설계한다.
@Generable(description: "배경 공간을 채우는 입자 레이어 하나")
struct ParticleLayer: Equatable {
    @Guide(description: "입자 이름. 사용자가 말한 단어를 최대한 그대로 살린 짧은 한국어 (예: 벚꽃잎, 반딧불, 빗방울, 불씨, 색종이)")
    var name: String

    @Guide(description: "입자 색")
    var color: MoodColor

    var shape: ParticleShape

    var motion: ParticleMotion

    @Guide(description: "입자 한 개의 크기(미터). 빗방울 0.01, 눈송이 0.02, 꽃잎 0.04, 나뭇잎 0.08, 안개 뭉치 0.4 정도", .range(0.005...0.5))
    var size: Double

    @Guide(description: "밀도. 0.1은 드물게, 1.0은 가득", .range(0.05...1.0))
    var density: Double

    @Guide(description: "속도. 0.1은 아주 느리게, 1.0은 빠르게", .range(0.05...1.0))
    var speed: Double

    @Guide(description: "스스로 빛나는지. 반딧불·불씨·별·마법 가루는 true, 꽃잎·눈·비·나뭇잎은 false")
    var glows: Bool
}

/// 온디바이스 언어 모델이 사용자의 이야기·분위기 설명을 해석해 만들어내는 장면 명세.
@Generable(description: "사용자의 이야기나 분위기 설명에 어울리는 몰입형 배경 장면 명세")
struct SceneMood: Equatable {
    @Guide(description: "장면을 요약하는 짧은 한국어 제목 (10자 이내)")
    var title: String

    @Guide(description: "콜슨AI가 사용자에게 건네는 짧고 친근한 한국어 한 문장 응답 (40자 이내)")
    var reply: String

    @Guide(description: "하늘 꼭대기(천정) 색상")
    var skyTop: MoodColor

    @Guide(description: "지평선 근처 하늘 색상")
    var skyHorizon: MoodColor

    @Guide(description: "바닥(지면) 색상")
    var ground: MoodColor

    @Guide(description: "콜슨AI 오브의 발광 색상. 장면 분위기와 조화롭게")
    var accent: MoodColor

    @Guide(description: "하늘의 천체")
    var celestial: CelestialBody

    @Guide(description: "밤하늘 별의 밀도. 0이면 없음, 1이면 가득", .range(0.0...1.0))
    var stars: Double

    @Guide(description: "안개·흐림 정도. 0이면 맑음, 1이면 짙은 안개", .range(0.0...1.0))
    var fog: Double

    @Guide(description: "공간을 채우는 입자 레이어. 사용자가 언급한 떠다니거나, 떨어지거나, 빛나는 사물을 최대한 그대로 반영한다. 해당하는 것이 없으면 빈 배열", .maximumCount(3))
    var particles: [ParticleLayer]
}

// MARK: - 기본값과 폴백

extension SceneMood {
    /// 앱을 처음 열었을 때 보여주는 차분한 기본 장면.
    static let `default` = SceneMood(
        title: "조용한 새벽",
        reply: "안녕하세요. 원하시는 분위기를 말씀해 주세요.",
        skyTop: MoodColor(hex: 0x0E1B33),
        skyHorizon: MoodColor(hex: 0x6E7FA6),
        ground: MoodColor(hex: 0x1C2233),
        accent: MoodColor(hex: 0x5AC8FA),
        celestial: .moon,
        stars: 0.35,
        fog: 0.25,
        particles: [
            ParticleLayer(name: "새벽 먼지", color: MoodColor(hex: 0xBFD3FF), shape: .glowDot, motion: .drift,
                          size: 0.012, density: 0.25, speed: 0.1, glows: true),
        ]
    )

    /// Apple Intelligence를 사용할 수 없을 때 키워드로 대략적인 장면을 만들어내는 폴백.
    /// 색 팔레트는 대표 상황으로 고르고, 입자는 언급된 사물을 키워드 표에서 최대 3개까지 찾아 넣는다.
    static func heuristic(from text: String) -> SceneMood {
        var mood = palette(for: text)
        let matched = ParticleLayer.layers(matching: text)
        if !matched.isEmpty {
            mood.particles = Array(matched.prefix(3))
        }
        return mood
    }

    private static func palette(for text: String) -> SceneMood {
        let lower = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { lower.contains($0) } }

        if has("우주", "은하", "space", "galaxy") {
            return SceneMood(
                title: "별의 바다", reply: "은하 한가운데로 모셔 드릴게요.",
                skyTop: MoodColor(hex: 0x02030A), skyHorizon: MoodColor(hex: 0x1B1040),
                ground: MoodColor(hex: 0x05060F), accent: MoodColor(hex: 0xB388FF),
                celestial: .none, stars: 1.0, fog: 0.05,
                particles: [ParticleLayer.catalog["별"]!]
            )
        }
        if has("비", "장마", "rain", "폭풍") {
            return SceneMood(
                title: "비 오는 저녁", reply: "빗소리가 어울리는 저녁으로 바꿔 드릴게요.",
                skyTop: MoodColor(hex: 0x1E2630), skyHorizon: MoodColor(hex: 0x5C6B7A),
                ground: MoodColor(hex: 0x2A3138), accent: MoodColor(hex: 0x7FB3FF),
                celestial: .none, stars: 0.0, fog: 0.7,
                particles: [ParticleLayer.catalog["비"]!]
            )
        }
        if has("눈", "겨울", "snow", "크리스마스") {
            return SceneMood(
                title: "고요한 눈밭", reply: "포근한 눈이 내리는 겨울로 꾸며 드릴게요.",
                skyTop: MoodColor(hex: 0x4B5B73), skyHorizon: MoodColor(hex: 0xC9D3E0),
                ground: MoodColor(hex: 0xE8EEF5), accent: MoodColor(hex: 0xBFE6FF),
                celestial: .none, stars: 0.0, fog: 0.5,
                particles: [ParticleLayer.catalog["눈"]!]
            )
        }
        if has("불", "캠프", "모닥", "fire", "camp") {
            return SceneMood(
                title: "모닥불 밤", reply: "타닥타닥 모닥불 곁으로 안내할게요.",
                skyTop: MoodColor(hex: 0x080A16), skyHorizon: MoodColor(hex: 0x3A2A1E),
                ground: MoodColor(hex: 0x2B2118), accent: MoodColor(hex: 0xFF9F43),
                celestial: .none, stars: 0.8, fog: 0.15,
                particles: [ParticleLayer.catalog["불씨"]!, ParticleLayer.catalog["별"]!]
            )
        }
        if has("바다", "해변", "ocean", "sea", "beach", "여름") {
            return SceneMood(
                title: "한낮의 해변", reply: "파도가 반짝이는 바다로 데려다 드릴게요.",
                skyTop: MoodColor(hex: 0x1E7BD9), skyHorizon: MoodColor(hex: 0xBFE9FF),
                ground: MoodColor(hex: 0x2A9FD6), accent: MoodColor(hex: 0x64D2FF),
                celestial: .sun, stars: 0.0, fog: 0.1,
                particles: [ParticleLayer.catalog["물보라"]!]
            )
        }
        if has("숲", "forest", "나무", "정글", "자연") {
            return SceneMood(
                title: "안개 숲", reply: "촉촉한 숲 속 공기로 채워 드릴게요.",
                skyTop: MoodColor(hex: 0x1F3B2E), skyHorizon: MoodColor(hex: 0x8FB89A),
                ground: MoodColor(hex: 0x24402D), accent: MoodColor(hex: 0x9BE15D),
                celestial: .none, stars: 0.0, fog: 0.6,
                particles: [ParticleLayer.catalog["반딧불"]!, ParticleLayer.catalog["나뭇잎"]!]
            )
        }
        if has("노을", "석양", "sunset", "저녁") {
            return SceneMood(
                title: "붉은 노을", reply: "하늘을 노을빛으로 물들여 드릴게요.",
                skyTop: MoodColor(hex: 0x2B1E4F), skyHorizon: MoodColor(hex: 0xFF8A5B),
                ground: MoodColor(hex: 0x3A2A33), accent: MoodColor(hex: 0xFFB36B),
                celestial: .sun, stars: 0.1, fog: 0.3,
                particles: [ParticleLayer.catalog["먼지"]!]
            )
        }
        if has("카페", "커피", "아늑", "cozy", "따뜻") {
            return SceneMood(
                title: "아늑한 카페", reply: "따뜻한 조명의 카페 분위기로 바꿔 드릴게요.",
                skyTop: MoodColor(hex: 0x2E2117), skyHorizon: MoodColor(hex: 0x8A6242),
                ground: MoodColor(hex: 0x3B2A1F), accent: MoodColor(hex: 0xFFC777),
                celestial: .none, stars: 0.0, fog: 0.35,
                particles: [ParticleLayer.catalog["먼지"]!]
            )
        }
        if has("밤", "night", "어둠", "달") {
            return SceneMood(
                title: "달빛 밤", reply: "은은한 달빛이 드는 밤으로 꾸며 드릴게요.",
                skyTop: MoodColor(hex: 0x050814), skyHorizon: MoodColor(hex: 0x233355),
                ground: MoodColor(hex: 0x0F1424), accent: MoodColor(hex: 0x9FC5FF),
                celestial: .moon, stars: 0.7, fog: 0.2,
                particles: [ParticleLayer.catalog["별"]!]
            )
        }
        return SceneMood(
            title: "맑은 아침", reply: "산뜻한 아침 공기로 채워 드릴게요.",
            skyTop: MoodColor(hex: 0x3D8BE0), skyHorizon: MoodColor(hex: 0xDDEFFF),
            ground: MoodColor(hex: 0x6F8F6B), accent: MoodColor(hex: 0x5AC8FA),
            celestial: .sun, stars: 0.0, fog: 0.15,
            particles: [ParticleLayer.catalog["먼지"]!]
        )
    }
}

// MARK: - 폴백용 입자 카탈로그

extension ParticleLayer {
    /// 자주 등장하는 사물의 대표 입자 설정.
    static let catalog: [String: ParticleLayer] = [
        "비": ParticleLayer(name: "빗방울", color: MoodColor(hex: 0xA9C4E6), shape: .streak, motion: .fall,
                            size: 0.012, density: 0.85, speed: 0.9, glows: false),
        "눈": ParticleLayer(name: "눈송이", color: MoodColor(hex: 0xFFFFFF), shape: .flake, motion: .fall,
                            size: 0.025, density: 0.6, speed: 0.2, glows: false),
        "벚꽃": ParticleLayer(name: "벚꽃잎", color: MoodColor(hex: 0xFFB7C5), shape: .petal, motion: .fall,
                              size: 0.045, density: 0.5, speed: 0.25, glows: false),
        "낙엽": ParticleLayer(name: "낙엽", color: MoodColor(hex: 0xD2691E), shape: .petal, motion: .fall,
                              size: 0.07, density: 0.35, speed: 0.3, glows: false),
        "나뭇잎": ParticleLayer(name: "나뭇잎", color: MoodColor(hex: 0x6FAF5A), shape: .petal, motion: .drift,
                                size: 0.05, density: 0.2, speed: 0.2, glows: false),
        "반딧불": ParticleLayer(name: "반딧불", color: MoodColor(hex: 0xD9FF6E), shape: .glowDot, motion: .drift,
                                size: 0.03, density: 0.3, speed: 0.15, glows: true),
        "불씨": ParticleLayer(name: "불씨", color: MoodColor(hex: 0xFF8A3D), shape: .spark, motion: .rise,
                              size: 0.015, density: 0.5, speed: 0.5, glows: true),
        "별": ParticleLayer(name: "별빛", color: MoodColor(hex: 0xFFFFFF), shape: .star, motion: .drift,
                            size: 0.02, density: 0.5, speed: 0.05, glows: true),
        "먼지": ParticleLayer(name: "햇살 먼지", color: MoodColor(hex: 0xF3E6C8), shape: .glowDot, motion: .drift,
                              size: 0.01, density: 0.35, speed: 0.1, glows: true),
        "비눗방울": ParticleLayer(name: "비눗방울", color: MoodColor(hex: 0xD6F0FF), shape: .bubble, motion: .rise,
                                  size: 0.06, density: 0.3, speed: 0.2, glows: false),
        "나비": ParticleLayer(name: "나비", color: MoodColor(hex: 0xFFC94D), shape: .feather, motion: .drift,
                              size: 0.06, density: 0.15, speed: 0.3, glows: false),
        "색종이": ParticleLayer(name: "색종이", color: MoodColor(hex: 0xFF5E7E), shape: .feather, motion: .fall,
                                size: 0.03, density: 0.6, speed: 0.4, glows: false),
        "안개": ParticleLayer(name: "안개", color: MoodColor(hex: 0xE6ECF2), shape: .glowDot, motion: .drift,
                              size: 0.45, density: 0.3, speed: 0.05, glows: false),
        "폭죽": ParticleLayer(name: "폭죽", color: MoodColor(hex: 0xFFD166), shape: .spark, motion: .burst,
                              size: 0.02, density: 0.9, speed: 0.9, glows: true),
        "물보라": ParticleLayer(name: "물보라", color: MoodColor(hex: 0xCFF2FF), shape: .glowDot, motion: .rise,
                                size: 0.012, density: 0.3, speed: 0.3, glows: true),
        "씨앗": ParticleLayer(name: "민들레 씨앗", color: MoodColor(hex: 0xFFFFFF), shape: .feather, motion: .drift,
                              size: 0.04, density: 0.2, speed: 0.15, glows: false),
        "마법": ParticleLayer(name: "마법 가루", color: MoodColor(hex: 0xC8A2FF), shape: .star, motion: .swirl,
                              size: 0.02, density: 0.6, speed: 0.4, glows: true),
        "재": ParticleLayer(name: "재", color: MoodColor(hex: 0x7A7A7A), shape: .flake, motion: .drift,
                            size: 0.015, density: 0.4, speed: 0.15, glows: false),
    ]

    /// 문장에서 언급된 사물을 찾아 해당 입자 레이어를 돌려준다.
    static func layers(matching text: String) -> [ParticleLayer] {
        let lower = text.lowercased()
        let table: [([String], String)] = [
            (["폭죽", "불꽃놀이", "firework"], "폭죽"),
            (["벚꽃", "꽃잎", "sakura", "cherry", "꽃비"], "벚꽃"),
            (["낙엽", "단풍", "가을", "autumn"], "낙엽"),
            (["반딧불", "firefl"], "반딧불"),
            (["비눗방울", "거품", "bubble", "물방울"], "비눗방울"),
            (["나비", "butterfl"], "나비"),
            (["색종이", "confetti", "축하", "파티", "생일"], "색종이"),
            (["민들레", "씨앗", "홀씨"], "씨앗"),
            (["마법", "magic", "요정", "fairy", "반짝"], "마법"),
            (["안개", "fog", "mist", "구름"], "안개"),
            (["불씨", "모닥", "캠프", "fire", "장작", "화로"], "불씨"),
            (["재가", "잿", "ash"], "재"),
            (["눈", "snow", "겨울"], "눈"),
            (["비", "rain", "장마", "소나기"], "비"),
            (["별", "우주", "은하", "star", "space"], "별"),
            (["나뭇잎", "숲", "잎사귀", "forest", "leaf"], "나뭇잎"),
            (["파도", "바다", "물보라", "wave"], "물보라"),
            (["먼지", "햇살", "dust", "오후"], "먼지"),
        ]
        var result: [ParticleLayer] = []
        for (keywords, key) in table where keywords.contains(where: { lower.contains($0) }) {
            if let layer = catalog[key], !result.contains(layer) {
                result.append(layer)
            }
        }
        return result
    }
}
