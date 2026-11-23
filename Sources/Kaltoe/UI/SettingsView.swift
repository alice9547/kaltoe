// 설정 화면 (docs/spec.md 5절). 값이 유효하면 바꾸는 즉시 저장·반영, 아니면 빨간 글씨로 이유를 보이고 저장하지 않는다.
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WorkdayStore          // 미리보기가 매초 따라가도록
    let settingsStore: SettingsStore
    let actions: AppActions
    /// 오늘 저장된 유동 모드 출근 기록 (미리보기용).
    let detectedClockIn: () -> Date?

    @State private var draft: WorkSettings
    @State private var errors: [SettingsError] = []
    @State private var launchAtLogin: Bool
    @State private var fontText: String
    /// 입력칸이 숫자가 아닐 때만 켜진다 (이때는 저장하지 않는다).
    @State private var fontTextError: SettingsError?
    @State private var wageText: String
    @State private var wageTextError: SettingsError?

    init(store: WorkdayStore, settingsStore: SettingsStore, actions: AppActions,
         detectedClockIn: @escaping () -> Date?) {
        self.store = store
        self.settingsStore = settingsStore
        self.actions = actions
        self.detectedClockIn = detectedClockIn
        _draft = State(initialValue: settingsStore.settings)
        _launchAtLogin = State(initialValue: actions.isLaunchAtLoginEnabled())
        _fontText = State(initialValue: String(settingsStore.settings.fontSize))
        _wageText = State(initialValue: settingsStore.settings.rateAmount.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("출근 방식") {
                Picker("", selection: $draft.mode) {
                    Text("유동 (처음 켠 시각)").tag(WorkMode.flexible)
                    Text("고정 (정해진 시각)").tag(WorkMode.fixed)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                switch draft.mode {
                case .flexible:
                    row("출근 인정 시작") { TimePicker(time: $draft.earliestStart) }
                    row("근무 시간") {
                        Stepper(value: hours, in: 0...16) { Text("\(draft.workMinutes / 60)시간").monospacedDigit() }
                        Stepper(value: minutes, in: 0...59) { Text("\(draft.workMinutes % 60)분").monospacedDigit() }
                    }
                case .fixed:
                    row("출근") { TimePicker(time: $draft.fixedStart) }
                    row("퇴근") { TimePicker(time: $draft.fixedEnd) }
                }
            }

            Divider()
            section("점심") {
                Toggle("점심 단계 사용", isOn: $draft.lunchEnabled)
                row("시작") { TimePicker(time: $draft.lunchStart) }.disabled(!draft.lunchEnabled)
                row("끝") { TimePicker(time: $draft.lunchEnd) }.disabled(!draft.lunchEnabled)
            }

            Divider()
            section("알림") {
                Toggle("점심 시작", isOn: $draft.notifyLunch).disabled(!draft.lunchEnabled)
                Toggle("퇴근 10분 전", isOn: $draft.notifyBeforeEnd)
                Toggle("퇴근 정각", isOn: $draft.notifyEnd)
            }

            Divider()
            section("야근") {
                Toggle("포괄임금제", isOn: $draft.comprehensivePay)
                row("연장수당 단가") {
                    TextField("최저시급 10,320", text: $wageText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: wageText) { _, text in applyWageText(text) }
                    Text("원").foregroundColor(.secondary)
                    Picker("", selection: $draft.rateUnit) {
                        Text("시간당").tag(PayRateUnit.hour)
                        Text("분당").tag(PayRateUnit.minute)
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    .disabled(draft.rateAmount == nil)
                }
                Text("비워 두면 최저시급(시간당 10,320원)으로 계산합니다. 참고용 금액입니다.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Divider()
            section("위젯") {
                row("위젯 모양") {
                    Picker("", selection: $draft.widgetStyle) {
                        Text("터미널").tag(WidgetStyle.terminal)
                        Text("말풍선").tag(WidgetStyle.bubble)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                row("글자 크기") {
                    TextField("", text: $fontText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .onChange(of: fontText) { _, text in applyFontText(text) }
                    Stepper("", value: fontStepper, in: WorkSettings.fontSizeRange)
                        .labelsHidden()
                    Text("px").foregroundColor(.secondary)
                }
            }

            Divider()
            Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in actions.setLaunchAtLogin(on) }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(WidgetText.previewLine(settings: draft, detectedClockIn: detectedClockIn(), now: store.snapshot.now))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                ForEach(shownErrors.indices, id: \.self) { i in
                    Text(shownErrors[i].message).font(.system(size: 12)).foregroundColor(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: draft) { _, new in
            errors = settingsStore.update(new)   // 유효하면 저장·반영, 아니면 오류만 돌려받음
        }
    }

    // MARK: 글자 크기 입력

    private var shownErrors: [SettingsError] { [fontTextError, wageTextError].compactMap { $0 } + errors }

    /// 숫자가 아니면 오류만 보이고 저장하지 않는다. 숫자면 초안에 넣고(범위 검사는 검증기가) 즉시 반영한다.
    private func applyFontText(_ text: String) {
        switch SettingsValidator.parseFontSize(text) {
        case .failure(let e): fontTextError = e
        case .success(let v):
            fontTextError = nil
            if draft.fontSize != v { draft.fontSize = v }
        }
    }

    /// 단가 입력칸: 비우면 최저시급, 숫자가 아니면 오류만 보이고 저장하지 않는다. 범위는 검증기가 본다.
    private func applyWageText(_ text: String) {
        switch SettingsValidator.parseRateAmount(text) {
        case .failure(let e): wageTextError = e
        case .success(let v):
            wageTextError = nil
            if draft.rateAmount != v { draft.rateAmount = v }
        }
    }

    private var fontStepper: Binding<Int> {
        Binding(get: { draft.fontSize },
                set: { draft.fontSize = $0; fontText = String($0); fontTextError = nil })
    }

    // MARK: 부품

    private var hours: Binding<Int> {
        Binding(get: { draft.workMinutes / 60 },
                set: { draft.workMinutes = $0 * 60 + draft.workMinutes % 60 })
    }

    private var minutes: Binding<Int> {
        Binding(get: { draft.workMinutes % 60 },
                set: { draft.workMinutes = draft.workMinutes / 60 * 60 + $0 })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// HH:mm 입력 — 시·분만 보이는 DatePicker 를 TimeOfDay 에 연결한다.
private struct TimePicker: View {
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker("", selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .environment(\.locale, Locale(identifier: "en_GB"))   // HH:mm 24시간제 (spec)
    }

    private var date: Binding<Date> {
        let cal = Calendar.current
        return Binding(
            get: { time.date(on: Date(), calendar: cal) },
            set: { d in
                let c = cal.dateComponents([.hour, .minute], from: d)
                time = TimeOfDay(c.hour ?? 0, c.minute ?? 0)
            })
    }
}
