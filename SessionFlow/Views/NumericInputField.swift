import SwiftUI

struct NumericInputField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = ""

    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    /// Width sized to fit the widest possible value
    private var fieldWidth: CGFloat {
        let maxDigits = max("\(range.lowerBound)".count, "\(range.upperBound)".count)
        return CGFloat(max(maxDigits, 2)) * 12 + 6
    }

    private var allowsNegative: Bool {
        range.lowerBound < 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Decrement button
            Button {
                if value - step >= range.lowerBound {
                    value -= step
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(value <= range.lowerBound ? colors.textMuted : colors.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(colors.divider)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.25)
            .disabled(value <= range.lowerBound)
            
            // Text field
            TextField("", text: $textValue)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(colors.textPrimary)
                .focused($isFocused)
                .padding(0)
                .labelsHidden()
                .frame(width: fieldWidth, height: 24)
                .fixedSize(horizontal: true, vertical: true)
                .onSubmit {
                    validateAndSet()
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isFocused ? colors.hoveredBackground : colors.border)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isFocused ? colors.borderStrong : Color.clear, lineWidth: 1)
                        )
                )
            .onChange(of: textValue) { _, newValue in
                if let intValue = parsedInt(from: newValue) {
                    if range.contains(intValue) {
                        value = intValue
                    }
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    validateAndSet()
                }
            }
            
            // Increment button
            Button {
                if value + step <= range.upperBound {
                    value += step
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(value >= range.upperBound ? colors.textMuted : colors.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(colors.divider)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.25)
            .disabled(value >= range.upperBound)
            
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .padding(0)
        .contentMargins(0)
        .onAppear {
            textValue = "\(value)"
        }
        .onChange(of: value) { _, newValue in
            textValue = "\(newValue)"
        }
    }
    
    private func validateAndSet() {
        if let intValue = parsedInt(from: textValue) {
            let clamped = min(max(intValue, range.lowerBound), range.upperBound)
            value = clamped
            textValue = "\(clamped)"
        } else {
            textValue = "\(value)"
        }
    }

    private func parsedInt(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { "0123456789".contains($0) }
        guard !digits.isEmpty else { return nil }
        let sign = allowsNegative && trimmed.first == "-" ? "-" : ""
        return Int(sign + digits)
    }
}
