import SwiftUI

/// A time input field with stepper buttons. When minutes are selected, the stepper adjusts by ±5.
/// When hours are selected, the stepper adjusts by ±1.
struct TimeInputField: View {
    @Binding var date: Date
    
    @State private var hourText: String = ""
    @State private var minuteText: String = ""
    @FocusState private var focusedPart: Part?
    
    private enum Part {
        case hour
        case minute
    }
    
    private let minuteStep = 5
    
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Hour field
            timePartField(
                text: $hourText,
                placeholder: "00",
                width: 24,
                focused: focusedPart == .hour
            )
            .focused($focusedPart, equals: .hour)
            .onSubmit { focusedPart = .minute }
            
            Text(":")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            
            // Minute field
            timePartField(
                text: $minuteText,
                placeholder: "00",
                width: 24,
                focused: focusedPart == .minute
            )
            .focused($focusedPart, equals: .minute)
            .onSubmit { focusedPart = nil }
            
            // Stepper
            VStack(spacing: 0) {
                Button {
                    step(up: true)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 14)
                }
                .buttonStyle(.plain)
                
                Button {
                    step(up: false)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            syncFromDate()
        }
        .onChange(of: date) { _, _ in
            syncFromDate()
        }
        .onChange(of: hourText) { _, newValue in
            let filtered = newValue.filter { "0123456789".contains($0) }
            if filtered != newValue { hourText = filtered }
            if let h = Int(filtered), (0...23).contains(h) {
                applyHourMinute(hour: h, minute: currentMinute)
            }
        }
        .onChange(of: minuteText) { _, newValue in
            let filtered = newValue.filter { "0123456789".contains($0) }
            if filtered != newValue { minuteText = filtered }
            if let m = Int(filtered), (0...59).contains(m) {
                applyHourMinute(hour: currentHour, minute: m)
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
                .fill(Color.white.opacity(focused ? 0.2 : 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(focused ? 0.4 : 0), lineWidth: 1)
                )
                .frame(width: width, height: 24)
            
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: width, height: 24)
                .padding(.horizontal, 2)
        }
    }
    
    private var currentHour: Int {
        Int(hourText.filter { "0123456789".contains($0) }) ?? 0
    }
    
    private var currentMinute: Int {
        Int(minuteText.filter { "0123456789".contains($0) }) ?? 0
    }
    
    private func syncFromDate() {
        let cal = Calendar.current
        let comp = cal.dateComponents([.hour, .minute], from: date)
        hourText = String(format: "%02d", comp.hour ?? 0)
        minuteText = String(format: "%02d", comp.minute ?? 0)
    }
    
    private func step(up: Bool) {
        if focusedPart == .hour {
            // Hour focused: step by 1
            let h = currentHour
            let newH = up ? min(23, h + 1) : max(0, h - 1)
            applyHourMinute(hour: newH, minute: currentMinute)
            hourText = String(format: "%02d", newH)
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
            minuteText = String(format: "%02d", newM)
            hourText = String(format: "%02d", comp.hour ?? 0)
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
        let h = min(23, max(0, currentHour))
        let m = min(59, max(0, currentMinute))
        hourText = String(format: "%02d", h)
        minuteText = String(format: "%02d", m)
        applyHourMinute(hour: h, minute: m)
    }
}
