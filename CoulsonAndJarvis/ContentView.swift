import SwiftUI

/// 컨트롤 패널 창. 분위기를 말하거나 입력하고, 공간 모드와 콜슨 호출을 다룬다.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var input = ""
    @State private var isTogglingSpace = false

    private let suggestions = [
        "비 내리는 밤, 창가의 재즈바",
        "한여름 오후의 해변",
        "별이 쏟아지는 우주 정거장",
        "눈 내리는 겨울 숲의 모닥불",
        "노을 지는 옥상에서 친구랑 수다",
    ]

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    spaceSection(mode: $model.spaceMode)
                    inputSection
                    suggestionSection
                    statusSection
                }
                .padding(24)
            }
            .navigationTitle("콜슨AI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.summonCoulson()
                    } label: {
                        Label("콜슨 호출", systemImage: "hand.wave")
                    }
                    .disabled(!model.isImmersiveSpaceOpen)
                }
            }
        }
        .task {
            await openSpaceIfNeeded()
        }
    }

    // MARK: - 섹션

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이야기나 분위기를 말해 주세요. 콜슨AI가 주변 공간을 그 느낌으로 꾸며 드립니다.")
                .font(.body)
                .foregroundStyle(.secondary)
            Label(model.director.backend.label, systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func spaceSection(mode: Binding<SpaceMode>) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("공간 모드", selection: mode) {
                    ForEach(SpaceMode.allCases) { spaceMode in
                        Label(spaceMode.label, systemImage: spaceMode.systemImage)
                            .tag(spaceMode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.isImmersiveSpaceOpen)

                if model.spaceMode == .immersive {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("다이얼(Digital Crown)을 돌려 몰입도를 조절하세요.", systemImage: "dial.medium")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: model.immersionAmount)
                            .tint(model.mood.accent.swiftUIColor)
                    }
                } else {
                    Label("현실 공간 위에 콜슨AI만 떠 있습니다. 손으로 잡아 옮겨 보세요.", systemImage: "hand.point.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await toggleSpace() }
                } label: {
                    Label(
                        model.isImmersiveSpaceOpen ? "공간 나가기" : "공간에 들어가기",
                        systemImage: model.isImmersiveSpaceOpen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                }
                .disabled(isTogglingSpace)
            }
        } label: {
            Label("공간", systemImage: "cube.transparent")
        }
    }

    private var inputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("예: 비 오는 밤의 조용한 카페", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }

                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.director.isThinking)

                    Button {
                        model.speech.toggle()
                    } label: {
                        Image(systemName: model.speech.isActive ? "mic.fill" : "mic")
                            .symbolEffect(.variableColor.iterative, isActive: model.speech.state == .listening)
                    }
                    .tint(model.speech.isActive ? .red : nil)
                }

                HStack(spacing: 8) {
                    Text(model.speech.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.speech.liveTranscript.isEmpty {
                        Text("“\(model.speech.liveTranscript)”")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Text("마이크를 켜 두면 “콜슨” 하고 부를 때 콜슨AI가 앞으로 오고, 이어서 말한 내용대로 배경이 바뀝니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Label("말하기", systemImage: "bubble.left.and.text.bubble.right")
        }
    }

    private var suggestionSection: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        input = suggestion
                        send()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
        .disabled(model.director.isThinking)
    }

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(model.mood.accent.swiftUIColor)
                        .frame(width: 12, height: 12)
                    Text(model.mood.title)
                        .font(.headline)
                    Spacer()
                    if model.director.isThinking {
                        ProgressView().controlSize(.small)
                    }
                }
                if !model.lastUserUtterance.isEmpty {
                    Text("“\(model.lastUserUtterance)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.mood.particles.isEmpty {
                    statusRow("입자", model.mood.particles.map(\.name).joined(separator: " · "), "wind")
                }
                Divider()
                statusRow("콜슨", model.coulsonStatus, "sparkle")
                statusRow("공간 인식", model.lidarStatus, "sensor")
                if let distance = model.shadowDistanceText {
                    statusRow("그림자 거리", distance, "ruler")
                }
                if let error = model.director.lastError {
                    statusRow("알림", error, "exclamationmark.triangle")
                }
            }
        } label: {
            Label("상태", systemImage: "info.circle")
        }
    }

    private func statusRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(2)
        }
        .font(.caption)
    }

    // MARK: - 동작

    private func send() {
        let text = input
        input = ""
        Task { await model.handleUtterance(text) }
    }

    private func openSpaceIfNeeded() async {
        guard !model.isImmersiveSpaceOpen, !isTogglingSpace else { return }
        isTogglingSpace = true
        defer { isTogglingSpace = false }
        switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
        case .opened:
            break
        case .userCancelled, .error:
            model.coulsonStatus = "이머시브 공간을 열 수 없어요. 버튼으로 다시 시도해 주세요."
        @unknown default:
            break
        }
    }

    private func toggleSpace() async {
        if model.isImmersiveSpaceOpen {
            isTogglingSpace = true
            await dismissImmersiveSpace()
            isTogglingSpace = false
        } else {
            await openSpaceIfNeeded()
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
