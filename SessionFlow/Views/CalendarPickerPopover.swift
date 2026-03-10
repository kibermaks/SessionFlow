import SwiftUI

struct CalendarPickerPopover: View {
    @Binding var selectedCalendar: String
    let calendars: [CalendarService.CalendarInfo]
    let accentColor: Color
    var onSelection: ((CalendarService.CalendarInfo) -> Void)?
    
    @State private var showingPopover = false
    
    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            pickerLabel
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
        .focusable(false)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var pickerLabel: some View {
        let calendarInfo = calendars.first { $0.name == selectedCalendar }

        return HStack(spacing: 10) {
            if !selectedCalendar.isEmpty, let info = calendarInfo {
                Circle()
                    .fill(info.color)
                    .frame(width: 12, height: 12)
            }
            Text(selectedCalendar.isEmpty ? "Select a calendar..." : selectedCalendar)
                .foregroundColor(selectedCalendar.isEmpty ? .white.opacity(0.5) : .white)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "0F172A").opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(accentColor.opacity(0.5), lineWidth: 2)
                )
        )
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(calendars) { info in
                Button {
                    guard !info.isExcluded else { return }
                    selectedCalendar = info.name
                    onSelection?(info)
                    showingPopover = false
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(info.color)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            if info.isExcluded {
                                Text("Hidden via Calendar Filters")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if info.name == selectedCalendar {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        info.name == selectedCalendar ?
                        accentColor.opacity(0.1) :
                        Color.clear
                    )
                    .opacity(info.isExcluded ? 0.35 : 1.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.1)
                .focusable(false)
                .disabled(info.isExcluded)

                if info.id != calendars.last?.id {
                    Divider()
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200, maxWidth: 280)
    }
}

// Compact version for SettingsPanel
struct CalendarPickerCompact: View {
    @Binding var selectedCalendar: String
    let calendars: [CalendarService.CalendarInfo]
    let accentColor: Color
    var onSelection: ((CalendarService.CalendarInfo) -> Void)?
    
    @State private var showingPopover = false
    
    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            compactLabel
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
        .focusable(false)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var isSelectedCalendarHidden: Bool {
        guard let info = calendars.first(where: { $0.name == selectedCalendar }) else { return false }
        return info.isExcluded
    }

    private var compactLabel: some View {
        let calendarInfo = calendars.first { $0.name == selectedCalendar }

        return HStack(spacing: 8) {
            if isSelectedCalendarHidden {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .help("This calendar is hidden from the timeline via Calendar Filters")
            }
            if let info = calendarInfo {
                Circle()
                    .fill(info.color)
                    .frame(width: 10, height: 10)
            }
            Text(selectedCalendar.isEmpty ? "Select..." : selectedCalendar)
                .foregroundColor(.white)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(minWidth: 120, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(calendars) { info in
                Button {
                    guard !info.isExcluded else { return }
                    selectedCalendar = info.name
                    onSelection?(info)
                    showingPopover = false
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(info.color)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            if info.isExcluded {
                                Text("Hidden via Calendar Filters")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if info.name == selectedCalendar {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        info.name == selectedCalendar ?
                        accentColor.opacity(0.1) :
                        Color.clear
                    )
                    .opacity(info.isExcluded ? 0.35 : 1.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(brightness: 0.1)
                .focusable(false)
                .disabled(info.isExcluded)

                if info.id != calendars.last?.id {
                    Divider()
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200, maxWidth: 280)
    }
}
