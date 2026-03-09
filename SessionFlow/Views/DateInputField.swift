import SwiftUI

/// A date input field with internal padding and stepper buttons.
struct DateInputField: View {
    @Binding var date: Date
    
    @FocusState private var isFocused: Bool
    
    private static let dateFormat = Date.FormatStyle()
        .month(.twoDigits)
        .day(.twoDigits)
        .year(.defaultDigits)
    
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Date field with internal padding
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(isFocused ? 0.2 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(isFocused ? 0.4 : 0), lineWidth: 1)
                    )
                    .frame(height: 24)
                
                TextField("", value: $date, format: Self.dateFormat)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
            }
            .frame(width: 110)
            
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
    }
    
    private func step(up: Bool) {
        let cal = Calendar.current
        if let newDate = cal.date(byAdding: .day, value: up ? 1 : -1, to: date) {
            date = newDate
        }
    }
}
