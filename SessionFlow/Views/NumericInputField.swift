import SwiftUI

struct NumericInputField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = ""
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    /// Width sized to fit the widest possible value
    private var fieldWidth: CGFloat {
        let maxDigits = "\(range.upperBound)".count
        return CGFloat(max(maxDigits, 2)) * 12 + 6
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
                    .foregroundColor(.white.opacity(value <= range.lowerBound ? 0.3 : 0.8))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1))
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
                .foregroundColor(.white)
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
                        .fill(Color.white.opacity(isFocused ? 0.2 : 0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(isFocused ? 0.4 : 0), lineWidth: 1)
                        )
                )
            .onChange(of: textValue) { _, newValue in
                if let intValue = Int(newValue.filter { "0123456789".contains($0) }) {
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
                    .foregroundColor(.white.opacity(value >= range.upperBound ? 0.3 : 0.8))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.25)
            .disabled(value >= range.upperBound)
            
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
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
        if let intValue = Int(textValue.filter { "0123456789".contains($0) }) {
            let clamped = min(max(intValue, range.lowerBound), range.upperBound)
            value = clamped
            textValue = "\(clamped)"
        } else {
            textValue = "\(value)"
        }
    }
}
