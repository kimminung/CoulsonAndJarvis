import Foundation
import RealityKit
import SwiftUI

/// 이머시브 공간의 표시 방식.
enum SpaceMode: String, CaseIterable, Identifiable {
    /// 실제 공간 위에 콜슨AI만 띄운다. 그림자가 실제 표면 위에 표시된다.
    case passthrough
    /// AI가 만든 배경으로 공간을 채운다. 다이얼(Digital Crown)로 몰입도를 조절한다.
    case immersive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .passthrough: return "현실 공간"
        case .immersive: return "몰입 배경"
        }
    }

    var systemImage: String {
        switch self {
        case .passthrough: return "visionpro"
        case .immersive: return "sparkles.rectangle.stack"
        }
    }
}

/// 창(컨트롤 패널)과 이머시브 공간이 공유하는 앱 상태.
@Observable
final class AppModel {
    static let immersiveSpaceID = "coulson.space"

    // 공간 상태
    var isImmersiveSpaceOpen = false
    var spaceMode: SpaceMode = .passthrough
    /// 다이얼로 조절되는 현재 몰입도(0~1). 몰입 배경 모드에서만 의미가 있다.
    var immersionAmount: Double = 0

    // 장면 상태
    var mood: SceneMood = .default
    var moodVersion = 0
    var lastUserUtterance = ""

    // 콜슨AI 상태
    var isCoulsonSummoned = false
    var coulsonStatus = "대기 중"
    var coulsonBubble: String? = SceneMood.default.reply
    /// 이 시각까지 콜슨이 "말하는 중"으로 표현된다.
    var speakingUntil: Date = .distantPast

    // 센서 상태 (ImmersiveView에서 갱신)
    var lidarStatus = "미확인"
    var shadowDistanceText: String?

    let director = SceneDirector()
    let speech = SpeechListener()

    init() {
        // 음성으로 "콜슨"을 부르면 호출, 문장이 끝나면 장면 연출.
        speech.onWakeWord = { [weak self] in
            self?.summonCoulson()
        }
        speech.onFinalUtterance = { [weak self] text in
            Task { await self?.handleUtterance(text) }
        }
    }

    /// 사용자의 문장(타이핑 또는 음성)을 받아 장면을 다시 연출한다.
    func handleUtterance(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastUserUtterance = trimmed
        coulsonStatus = "생각 중…"
        coulsonBubble = nil

        let newMood = await director.direct(trimmed)
        mood = newMood
        moodVersion += 1
        coulsonBubble = newMood.reply
        coulsonStatus = "\"\(newMood.title)\" 적용"
        speakingUntil = Date.now.addingTimeInterval(3.5)
    }

    /// "콜슨" 하고 부르면 콜슨AI가 사용자 앞으로 온다.
    func summonCoulson() {
        isCoulsonSummoned = true
        coulsonStatus = "네, 부르셨나요?"
        coulsonBubble = "네, 여기 있어요."
        speakingUntil = Date.now.addingTimeInterval(2.0)
    }
}
