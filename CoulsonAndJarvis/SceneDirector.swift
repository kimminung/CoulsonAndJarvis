import Foundation
import FoundationModels

/// Apple Foundation Models(온디바이스)로 사용자의 말을 해석해 `SceneMood`를 만들어내는 연출가.
/// 모델을 사용할 수 없으면 키워드 기반 폴백으로 동작해 앱이 항상 응답하도록 한다.
@Observable
final class SceneDirector {

    enum Backend: Equatable {
        case appleIntelligence
        case fallback(reason: String)

        var label: String {
            switch self {
            case .appleIntelligence: return "Apple Intelligence (온디바이스)"
            case .fallback(let reason): return "키워드 폴백 · \(reason)"
            }
        }
    }

    private(set) var backend: Backend = .fallback(reason: "확인 중")
    private(set) var isThinking = false
    private(set) var lastError: String?

    private var session: LanguageModelSession?

    private static let instructions = """
    The person's locale is ko_KR.
    You are "콜슨AI" (Coulson AI), a calm and witty spatial assistant living inside an Apple Vision Pro immersive space, \
    similar to JARVIS. The person will describe a story, a mood, a memory, or just chat casually.
    Your job: translate what they say into a simple, universally understandable immersive background scene.
    Rules:
    - Choose colors that a typical person would associate with the described time of day, weather, place, and emotion.
    - Keep skyTop darker than skyHorizon unless the scene is intentionally strange.
    - Use stars only for night or space scenes. Use fog for rainy, misty, dreamy or melancholic moods.
    - `particles` are the most important way to reflect the person's exact words. For EVERY physical thing they \
    mention that could float, fall, fly, glow, or scatter (꽃잎, 비, 눈, 반딧불, 불씨, 별, 먼지, 비눗방울, 나비, 색종이, \
    낙엽, 깃털, 안개, 폭죽, 물보라, 씨앗, 마법 가루 ...), add one layer (max 3) whose `name` keeps the person's own \
    word, and choose the closest `shape`, a realistic `color`, `size`, `density`, `speed`, and `motion`. \
    Examples: 비 → streak/fall/blue-gray/0.012/fast; 벚꽃 → petal/fall/pink/0.035/slow; 반딧불 → glowDot/drift/yellow-green/glows; \
    불씨 → spark/rise/orange/glows; 폭죽 → spark/burst/gold/glows; 나비 → feather/drift/yellow; 안개 → glowDot/drift/white/size 0.4. \
    If nothing physical is mentioned, infer 0–1 subtle layer that fits the mood (e.g. 햇살 먼지 for cozy, 별빛 for night).
    - `reply` MUST be one short friendly Korean sentence spoken by 콜슨AI. `title` MUST be short Korean.
    - Never refuse; if the request is vague, pick a pleasant, calm scene.
    """

    init() {
        refreshAvailability()
    }

    /// 모델 사용 가능 여부를 다시 확인하고 세션을 준비한다.
    func refreshAvailability() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            backend = .appleIntelligence
            if session == nil {
                let newSession = LanguageModelSession(model: model, instructions: Self.instructions)
                newSession.prewarm()
                session = newSession
            }
        case .unavailable(let reason):
            session = nil
            backend = .fallback(reason: Self.describe(reason))
        }
    }

    /// 사용자의 문장을 장면 명세로 바꾼다. 실패하면 폴백 결과를 돌려준다.
    func direct(_ text: String) async -> SceneMood {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }

        isThinking = true
        lastError = nil
        defer { isThinking = false }

        guard case .appleIntelligence = backend, let session else {
            return SceneMood.heuristic(from: trimmed)
        }

        // 세션이 너무 길어지면 컨텍스트 초과를 피하기 위해 새 세션으로 교체한다.
        if session.transcript.count > 24 {
            let fresh = LanguageModelSession(model: .default, instructions: Self.instructions)
            self.session = fresh
        }

        do {
            let options = GenerationOptions(temperature: 0.6, maximumResponseTokens: 900)
            let response = try await (self.session ?? session).respond(
                to: "사용자의 말: \"\(trimmed)\"\n이 말에 어울리는 배경 장면을 만들어 주세요.",
                generating: SceneMood.self,
                options: options
            )
            return response.content
        } catch let error as LanguageModelError {
            lastError = Self.describe(error)
            // 컨텍스트 초과 시 세션을 새로 만들고 폴백을 반환한다.
            if case .contextSizeExceeded = error {
                self.session = LanguageModelSession(model: .default, instructions: Self.instructions)
            }
            return SceneMood.heuristic(from: trimmed)
        } catch {
            lastError = error.localizedDescription
            return SceneMood.heuristic(from: trimmed)
        }
    }

    // MARK: - 설명 문자열

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "기기가 Apple Intelligence를 지원하지 않음"
        case .appleIntelligenceNotEnabled: return "설정에서 Apple Intelligence가 꺼져 있음"
        case .modelNotReady: return "모델 다운로드 대기 중"
        @unknown default: return "모델을 사용할 수 없음"
        }
    }

    private static func describe(_ error: LanguageModelError) -> String {
        switch error {
        case .contextSizeExceeded: return "대화가 길어져 세션을 새로 시작했어요."
        case .guardrailViolation: return "이 요청은 처리할 수 없어 기본 장면으로 대신했어요."
        case .refusal: return "모델이 응답하지 않아 기본 장면으로 대신했어요."
        case .unsupportedLanguageOrLocale: return "지원하지 않는 언어예요."
        case .rateLimited: return "잠시 후 다시 시도해 주세요."
        default: return error.localizedDescription
        }
    }
}
