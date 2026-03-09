import SwiftUI

struct PresetManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    
    @State private var presets: [Preset] = []
    @State private var showingNewPresetSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0F172A")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sectionView(title: "All Presets", icon: "bookmark.fill") {
                            if presets.isEmpty {
                                emptyPresetsView
                            } else {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    ForEach(presets) { preset in
                                        PresetCard(preset: preset, isCustom: true) {
                                            applyPreset(preset)
                                        } onDelete: {
                                            deletePreset(preset)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewPresetSheet = true
                    } label: {
                        Label("New Preset", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadPresets()
        }
        .sheet(isPresented: $showingNewPresetSheet) {
            NewPresetSheet { preset in
                saveNewPreset(preset)
            }
            .environmentObject(schedulingEngine)
        }
    }
    
    // MARK: - Section View
    
    private func sectionView<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            content()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyPresetsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No presets found")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
            
            Button("Create Preset") {
                showingNewPresetSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "8B5CF6"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    // MARK: - Actions
    
    private func loadPresets() {
        presets = PresetStorage.shared.loadPresets()
    }
    
    private func applyPreset(_ preset: Preset) {
        schedulingEngine.applyPreset(preset)
        dismiss()
    }
    
    private func saveNewPreset(_ preset: Preset) {
        PresetStorage.shared.addPreset(preset)
        loadPresets()
    }
    
    private func updatePreset(_ preset: Preset) {
        PresetStorage.shared.updatePreset(preset)
        loadPresets()
    }
    
    private func deletePreset(_ preset: Preset) {
        PresetStorage.shared.deletePreset(preset)
        loadPresets()
    }
}

// MARK: - Preset Card

struct PresetCard: View {
    let preset: Preset
    let isCustom: Bool
    let onApply: () -> Void
    var onDelete: (() -> Void)?
    
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: preset.icon)
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "8B5CF6"))
                
                HStack(spacing: 4) {
                    Text(preset.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if schedulingEngine.currentPresetId == preset.id && schedulingEngine.isPresetModified(preset) {
                         Text("*")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "F59E0B")) // Amber/Orange
                    }
                }
                
                Spacer()
                
                if isCustom && isHovered {
                    Button {
                        onDelete?()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Work: \(preset.workSessionCount) × \(preset.workSessionDuration)m")
                    Spacer()
                }
                HStack {
                    Text("Side: \(preset.sideSessionCount) × \(preset.sideSessionDuration)m")
                    Spacer()
                }
                Text("Pattern: \(preset.pattern.rawValue)")
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.6))
            
            // Calendar mapping
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text(preset.calendarMapping.workCalendarName)
                    .lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundColor(Color(hex: "3B82F6"))
            
            // Apply Button
            Button(action: onApply) {
                Text("Apply")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(hex: "8B5CF6"))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(isHovered ? 0.08 : 0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - New Preset Sheet

struct NewPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var schedulingEngine: SchedulingEngine
    
    @State private var presetName = ""
    @State private var selectedIcon = "calendar"
    
    let onSave: (Preset) -> Void
    
    private let iconOptions = [
        // Basic & Work
        "calendar", "briefcase.fill", "star.fill", "sun.max.fill",
        "moon.fill", "bolt.fill", "leaf.fill", "flame.fill",
        "brain.head.profile", "target", "clock.fill", "book.fill",
        // Productivity & Tech
        "hammer.fill", "laptopcomputer", "terminal.fill", "music.note",
        "paintbrush.fill", "pencil.and.outline", "keyboard", "command",
        "cpu", "network", "server.rack", "square.stack.3d.up.fill",
        // Activity & Life
        "sportscourt.fill", "gamecontroller.fill", "cart.fill", "airplane",
        "shippingbox.fill", "cup.and.saucer.fill", "fork.knife", "pills.fill",
        "heart.fill", "house.fill", "building.2.fill", "bicycle"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Preset Details") {
                    TextField("Preset Name", text: $presetName)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Icon").font(.caption).foregroundColor(.secondary)
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 10) {
                                ForEach(iconOptions, id: \.self) { icon in
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .frame(width: 40, height: 40)
                                        .background(selectedIcon == icon ? Color(hex: "8B5CF6") : Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .onTapGesture {
                                            selectedIcon = icon
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 180)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Current Settings Preview") {
                    LabeledContent("Work Sessions", value: "\(schedulingEngine.workSessions)")
                    LabeledContent("Side Sessions", value: "\(schedulingEngine.sideSessions)")
                    LabeledContent("Pattern", value: schedulingEngine.pattern.rawValue)
                    LabeledContent("Work Calendar", value: schedulingEngine.workCalendarName)
                    LabeledContent("Side Calendar", value: schedulingEngine.sideCalendarName)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let preset = schedulingEngine.saveAsPreset(
                            name: presetName,
                            icon: selectedIcon
                        )
                        onSave(preset)
                        dismiss()
                    }
                    .disabled(presetName.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 450)
    }
}


#Preview {
    PresetManagerView()
        .environmentObject(SchedulingEngine())
}
