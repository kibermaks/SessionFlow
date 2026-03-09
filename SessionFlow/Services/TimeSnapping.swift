import Foundation

enum TimeSnapping {
    /// Rounds a date to the nearest N-minute interval boundary.
    /// Unlike SchedulingEngine.roundToNextInterval (which rounds UP),
    /// this rounds to the NEAREST boundary for intuitive drag behavior.
    static func snapToNearest(_ date: Date, intervalMinutes: Int = 5) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let totalSeconds = date.timeIntervalSince(dayStart)
        let intervalSeconds = Double(intervalMinutes * 60)
        let rounded = (totalSeconds / intervalSeconds).rounded() * intervalSeconds
        return dayStart.addingTimeInterval(rounded)
    }
}
