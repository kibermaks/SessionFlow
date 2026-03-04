import SwiftUI

struct TasksPanel: View {
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @ObservedObject private var taskLineHistory = TaskLineHistory.shared
    var isLocked: Bool = false

    @StateObject private var workAction = TaskEditorAction()
    @StateObject private var sideAction = TaskEditorAction()
    @StateObject private var deepAction = TaskEditorAction()

    @State private var isWorkFocused = false
    @State private var isSideFocused = false
    @State private var isDeepFocused = false

    @State private var confirmingClear: SessionType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                taskSection(
                    title: "Work Tasks",
                    sessionType: .work,
                    icon: "briefcase.fill",
                    iconColor: Color(hex: "8B5CF6"),
                    isEnabled: $schedulingEngine.useWorkTasks,
                    text: $schedulingEngine.workTasks,
                    action: workAction,
                    isFocused: $isWorkFocused
                )

                Divider().background(Color.white.opacity(0.1))

                taskSection(
                    title: "Side Tasks",
                    sessionType: .side,
                    icon: "star.fill",
                    iconColor: Color(hex: "3B82F6"),
                    isEnabled: $schedulingEngine.useSideTasks,
                    text: $schedulingEngine.sideTasks,
                    action: sideAction,
                    isFocused: $isSideFocused
                )

                Divider().background(Color.white.opacity(0.1))

                taskSection(
                    title: "Deep Tasks",
                    sessionType: .deep,
                    icon: "bolt.circle.fill",
                    iconColor: Color(hex: "10B981"),
                    isEnabled: $schedulingEngine.useDeepTasks,
                    text: $schedulingEngine.deepTasks,
                    action: deepAction,
                    isFocused: $isDeepFocused
                )
            }
            .padding()
            .disabled(isLocked)
        }
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private func taskSection(
        title: String,
        sessionType: SessionType,
        icon: String,
        iconColor: Color,
        isEnabled: Binding<Bool>,
        text: Binding<String>,
        action: TaskEditorAction,
        isFocused: Binding<Bool>
    ) -> some View {
        let isConfirming = confirmingClear == sessionType
        let hasText = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let historyLines = taskLineHistory.getLines(for: sessionType)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()

                // History menu
                if !historyLines.isEmpty {
                    Menu {
                        ForEach(historyLines, id: \.self) { line in
                            Button(line) {
                                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    text.wrappedValue = line
                                } else {
                                    text.wrappedValue += "\n" + line
                                }
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            taskLineHistory.clearLines(for: sessionType)
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Previously used tasks")
                }

                // Clear button with two-click confirmation
                Button {
                    handleClearTap(sessionType: sessionType, text: text)
                } label: {
                    Image(systemName: isConfirming ? "trash.fill" : "trash")
                        .font(.system(size: 11))
                        .foregroundColor(isConfirming ? Color(hex: "EF4444") : .white.opacity(hasText ? 0.5 : 0.2))
                        .frame(width: 24, height: 24)
                        .background(isConfirming ? Color(hex: "EF4444").opacity(0.15) : Color.white.opacity(0.05))
                        .cornerRadius(4)
                        .animation(.easeInOut(duration: 0.15), value: isConfirming)
                }
                .buttonStyle(.plain)
                .disabled(!hasText && !isConfirming)
                .help(isConfirming ? "Click again to confirm" : "Clear all tasks")

                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(iconColor)
            }

            HStack(alignment: .top, spacing: 12) {
                TaskEditor(text: text, isFocused: isFocused, action: action)
                    .frame(height: 120)
                    .onChange(of: isFocused.wrappedValue) { _, focused in
                        if !focused {
                            let lines = text.wrappedValue
                                .components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            if !lines.isEmpty {
                                taskLineHistory.addLines(lines, for: sessionType)
                            }
                        }
                    }

                VStack(spacing: 8) {
                    reorderButton(icon: "chevron.up", isEnabled: isFocused.wrappedValue, action: { action.moveUp.send() })
                    reorderButton(icon: "chevron.down", isEnabled: isFocused.wrappedValue, action: { action.moveDown.send() })
                    Spacer()
                }
            }

            Text("One title per line. Use Ctrl + Cmd + Up/Down to reorder.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func handleClearTap(sessionType: SessionType, text: Binding<String>) {
        if confirmingClear == sessionType {
            // Second click — save lines to history, then clear
            let lines = text.wrappedValue
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            taskLineHistory.addLines(lines, for: sessionType)
            text.wrappedValue = ""
            withAnimation(.easeInOut(duration: 0.15)) {
                confirmingClear = nil
            }
        } else {
            // First click — enter confirming state
            withAnimation(.easeInOut(duration: 0.15)) {
                confirmingClear = sessionType
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if confirmingClear == sessionType {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        confirmingClear = nil
                    }
                }
            }
        }
    }

    private func reorderButton(icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isEnabled ? .white : .white.opacity(0.2))
                .frame(width: 24, height: 24)
                .background(isEnabled ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Task Line History

class TaskLineHistory: ObservableObject {
    static let shared = TaskLineHistory()

    private let workKey = "TaskScheduler.WorkTaskLines"
    private let sideKey = "TaskScheduler.SideTaskLines"
    private let deepKey = "TaskScheduler.DeepTaskLines"

    @Published private(set) var workLines: [String] = []
    @Published private(set) var sideLines: [String] = []
    @Published private(set) var deepLines: [String] = []

    private init() {
        workLines = UserDefaults.standard.stringArray(forKey: workKey) ?? []
        sideLines = UserDefaults.standard.stringArray(forKey: sideKey) ?? []
        deepLines = UserDefaults.standard.stringArray(forKey: deepKey) ?? []
    }

    func addLines(_ lines: [String], for type: SessionType) {
        var current = getLines(for: type)
        for line in lines where !line.isEmpty {
            current.removeAll { $0 == line }
            current.insert(line, at: 0)
        }
        if current.count > 50 {
            current = Array(current.prefix(50))
        }
        save(current, for: type)
    }

    func removeLine(_ line: String, from type: SessionType) {
        var current = getLines(for: type)
        current.removeAll { $0 == line }
        save(current, for: type)
    }

    func clearLines(for type: SessionType) {
        save([], for: type)
    }

    func getLines(for type: SessionType) -> [String] {
        switch type {
        case .work: return workLines
        case .side: return sideLines
        case .deep: return deepLines
        default: return []
        }
    }

    private func save(_ lines: [String], for type: SessionType) {
        let key: String
        switch type {
        case .work: key = workKey; workLines = lines
        case .side: key = sideKey; sideLines = lines
        case .deep: key = deepKey; deepLines = lines
        default: return
        }
        UserDefaults.standard.set(lines, forKey: key)
    }
}

#Preview {
    TasksPanel()
        .environmentObject(SchedulingEngine())
        .frame(width: 320, height: 600)
        .background(Color(hex: "0F172A"))
}
