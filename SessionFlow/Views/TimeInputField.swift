import SwiftUI

/// A time input field with stepper buttons. When minutes are selected, the stepper adjusts by ±5.
/// When hours are selected, the stepper adjusts by ±1.
struct TimeInputField: View {
    @Binding var date: Date

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @State private var hourText: String = ""
    @State private var minuteText: String = ""
    @State private var period: DayPeriod = .am
    @FocusState private var focusedPart: Part?
    
    private enum Part {
        case hour
        case minute
    }

    private enum DayPeriod: String, CaseIterable, Identifiable {
        case am = "AM"
        case pm = "PM"

        var id: String { rawValue }
    }
    
    private let minuteStep = 5

    static var preferredControlWidth: CGFloat {
        usesTwelveHourClock() ? 168 : 100
    }

    private var usesTwelveHourClock: Bool {
        Self.usesTwelveHourClock()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Hour field
            timePartField(
                text: $hourText,
                placeholder: usesTwelveHourClock ? "12" : "00",
                width: 24,
                focused: focusedPart == .hour
            )
            .focused($focusedPart, equals: .hour)
            .onSubmit { focusedPart = .minute }
            
            Text(":")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(colors.textSecondary)
            
            // Minute field
            timePartField(
                text: $minuteText,
                placeholder: "00",
                width: 24,
                focused: focusedPart == .minute
            )
            .focused($focusedPart, equals: .minute)
            .onSubmit { focusedPart = nil }

            if usesTwelveHourClock {
                Picker("", selection: $period) {
                    ForEach(DayPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 64, height: 24)
                .controlSize(.small)
                .onChange(of: period) { _, _ in
                    applyCurrentTextToDate()
                }
            }
            
            // Stepper
            VStack(spacing: 0) {
                Button {
                    step(up: true)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 20, height: 14)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.25)

                Button {
                    step(up: false)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 20, height: 14)
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.25)
            }
        }
        .frame(width: Self.preferredControlWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            syncFromDate()
        }
        .onChange(of: date) { _, _ in
            syncFromDate()
        }
        .onChange(of: usesTwelveHourClock) { _, _ in
            syncFromDate()
        }
        .onChange(of: hourText) { _, newValue in
            let filtered = newValue.filter { "0123456789".contains($0) }
            if filtered != newValue { hourText = filtered }
            if let h = Int(filtered), validHourRange.contains(h) {
                applyHourMinute(hour: absoluteHour(displayHour: h), minute: currentMinute)
            }
        }
        .onChange(of: minuteText) { _, newValue in
            let filtered = newValue.filter { "0123456789".contains($0) }
            if filtered != newValue { minuteText = filtered }
            if let m = Int(filtered), (0...59).contains(m) {
                applyHourMinute(hour: absoluteHour(displayHour: currentDisplayHour), minute: m)
            }
        }
        .onChange(of: focusedPart) { _, part in
            if part == nil {
                validateAndClamp()
            }
        }
    }
    
    private func timePartField(text: Binding<String>, placeholder: String, width: CGFloat, focused: Bool) -> some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 6)
                .fill(focused ? colors.hoveredBackground : colors.border)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(focused ? colors.borderStrong : Color.clear, lineWidth: 1)
                )
                .frame(width: width, height: 24)
            
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(colors.textPrimary)
                .frame(width: width, height: 24)
                .padding(.horizontal, 2)
        }
    }
    
    private var currentDisplayHour: Int {
        Int(hourText.filter { "0123456789".contains($0) }) ?? 0
    }
    
    private var currentMinute: Int {
        Int(minuteText.filter { "0123456789".contains($0) }) ?? 0
    }

    private var validHourRange: ClosedRange<Int> {
        usesTwelveHourClock ? 1...12 : 0...23
    }
    
    private func syncFromDate() {
        let cal = Calendar.current
        let comp = cal.dateComponents([.hour, .minute], from: date)
        let hour = comp.hour ?? 0
        if usesTwelveHourClock {
            hourText = "\(displayHour(from: hour))"
            period = hour < 12 ? .am : .pm
        } else {
            hourText = String(format: "%02d", hour)
        }
        minuteText = String(format: "%02d", comp.minute ?? 0)
    }
    
    private func step(up: Bool) {
        if focusedPart == .hour {
            // Hour focused: step by 1
            let cal = Calendar.current
            let hour = cal.component(.hour, from: date)
            let newHour = up ? min(23, hour + 1) : max(0, hour - 1)
            applyHourMinute(hour: newHour, minute: currentMinute)
            syncFromDate()
        } else {
            // Minute focused (or neither): step by 5
            let m = currentMinute
            var newM = up ? m + minuteStep : m - minuteStep
            var hourDelta = 0
            if newM >= 60 {
                newM = 0
                hourDelta = 1
            } else if newM < 0 {
                newM = 60 + newM  // e.g. -5 -> 55
                hourDelta = -1
            }
            let cal = Calendar.current
            var comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let rawHour = (comp.hour ?? 0) + hourDelta
            comp.hour = ((rawHour % 24) + 24) % 24
            comp.minute = newM
            if let newDate = cal.date(from: comp) {
                date = newDate
            }
            syncFromDate()
        }
    }
    
    private func applyHourMinute(hour: Int, minute: Int) {
        let cal = Calendar.current
        var comp = cal.dateComponents([.year, .month, .day], from: date)
        comp.hour = min(23, max(0, hour))
        comp.minute = min(59, max(0, minute))
        comp.second = 0
        if let newDate = cal.date(from: comp) {
            date = newDate
        }
    }
    
    private func validateAndClamp() {
        let h = min(validHourRange.upperBound, max(validHourRange.lowerBound, currentDisplayHour))
        let m = min(59, max(0, currentMinute))
        hourText = usesTwelveHourClock ? "\(h)" : String(format: "%02d", h)
        minuteText = String(format: "%02d", m)
        applyHourMinute(hour: absoluteHour(displayHour: h), minute: m)
    }

    private func applyCurrentTextToDate() {
        let h = min(validHourRange.upperBound, max(validHourRange.lowerBound, currentDisplayHour))
        let m = min(59, max(0, currentMinute))
        applyHourMinute(hour: absoluteHour(displayHour: h), minute: m)
        syncFromDate()
    }

    private func absoluteHour(displayHour: Int) -> Int {
        guard usesTwelveHourClock else {
            return min(23, max(0, displayHour))
        }

        let normalizedHour = min(12, max(1, displayHour))
        switch period {
        case .am:
            return normalizedHour == 12 ? 0 : normalizedHour
        case .pm:
            return normalizedHour == 12 ? 12 : normalizedHour + 12
        }
    }

    private func displayHour(from absoluteHour: Int) -> Int {
        let hour = ((absoluteHour % 24) + 24) % 24
        let displayHour = hour % 12
        return displayHour == 0 ? 12 : displayHour
    }

    private static func usesTwelveHourClock() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return format.contains("a")
    }
}
