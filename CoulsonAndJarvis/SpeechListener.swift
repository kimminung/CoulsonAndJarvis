import AVFoundation
import CoreMedia
import Foundation
import Speech

/// 온디바이스 음성 인식(SpeechAnalyzer)으로 사용자의 말을 듣는다.
/// "콜슨"이라는 호출어가 들리면 `onWakeWord`를, 문장이 끝나면 `onFinalUtterance`를 호출한다.
@Observable
final class SpeechListener {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)

        var label: String {
            switch self {
            case .idle: return "마이크 꺼짐"
            case .preparing: return "음성 모델 준비 중…"
            case .listening: return "듣고 있어요"
            case .unavailable(let reason): return "음성 인식 불가 · \(reason)"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var liveTranscript = ""

    var onWakeWord: (() -> Void)?
    var onFinalUtterance: ((String) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var captureProvider: CaptureInputSequenceProvider?
    private var listenTask: Task<Void, Never>?

    private static let wakeWords = ["콜슨", "콜 슨", "coulson", "colson"]

    var isActive: Bool {
        state == .listening || state == .preparing
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard listenTask == nil else { return }
        state = .preparing
        liveTranscript = ""
        listenTask = Task { await runSession() }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        captureProvider?.captureSession.stopRunning()
        captureProvider = nil
        analyzer = nil
        if case .unavailable = state {
            // 오류 메시지는 사용자가 볼 수 있게 남겨둔다.
        } else {
            state = .idle
        }
    }

    // MARK: - 세션 실행

    private func runSession() async {
        defer { listenTask = nil }
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                state = .unavailable("마이크 권한이 필요합니다")
                return
            }

            let preferred = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ko_KR"))
            let fallback = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            guard let locale = preferred ?? fallback else {
                state = .unavailable("지원되는 언어가 없습니다")
                return
            }

            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

            // 필요한 온디바이스 음성 모델이 없으면 내려받는다.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }

            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                state = .unavailable("마이크를 찾을 수 없습니다")
                return
            }

            let provider = try await CaptureInputSequenceProvider.providerWithSession(
                from: microphone,
                compatibleWith: [transcriber]
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            self.captureProvider = provider

            provider.captureSession.startRunning()
            try Task.checkCancellation()
            state = .listening

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.consumeResults(from: transcriber)
                }
                group.addTask {
                    let inputs = provider.analyzerInputs
                    if let lastTime = try await analyzer.analyzeSequence(inputs) {
                        try await analyzer.finalizeAndFinish(through: lastTime)
                    }
                }
                try await group.waitForAll()
            }
            if case .listening = state { state = .idle }
        } catch is CancellationError {
            if case .listening = state { state = .idle }
        } catch {
            state = .unavailable(error.localizedDescription)
            captureProvider?.captureSession.stopRunning()
            captureProvider = nil
            analyzer = nil
        }
    }

    private func consumeResults(from transcriber: SpeechTranscriber) async throws {
        for try await result in transcriber.results {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isFinal {
                liveTranscript = ""
                handleFinal(text)
            } else {
                liveTranscript = text
            }
        }
    }

    /// 확정된 문장을 처리한다. 호출어를 감지하고, 남은 문장을 명령으로 넘긴다.
    private func handleFinal(_ text: String) {
        guard !text.isEmpty else { return }
        let lower = text.lowercased()
        var command = text

        if let wake = Self.wakeWords.first(where: { lower.contains($0) }) {
            onWakeWord?()
            if let range = lower.range(of: wake) {
                // 호출어를 제외한 나머지만 명령으로 사용한다.
                let start = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                command = String(text[start...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?아야"))
            }
        }

        // 너무 짧은 말(예: "응", "네")은 장면을 바꾸지 않는다.
        guard command.count >= 3 else { return }
        onFinalUtterance?(command)
    }
}
