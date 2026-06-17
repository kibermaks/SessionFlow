import CoreGraphics
import Foundation
import Testing
@testable import SessionFlow

struct TimelineTimeScaleTests {
    @Test func effectiveEndHourKeepsExtendedScheduleVisible() {
        let hiddenNight = scale(hideNightHours: true, dayStartHour: 8, dayEndHour: 18, scheduleEndHour: 26)
        let fullDay = scale(hideNightHours: false, dayStartHour: 8, dayEndHour: 18, scheduleEndHour: 22)

        #expect(hiddenNight.effectiveEndHour == 26)
        #expect(hiddenNight.visibleHours == Array(8..<26))
        #expect(hiddenNight.contentHeight == 1_660)
        #expect(fullDay.effectiveEndHour == 24)
        #expect(fullDay.visibleHours == Array(0..<24))
    }

    @Test func yPositionAndDateOffsetAreInverseWithHiddenNightOffset() {
        let scale = scale(hideNightHours: true, dayStartHour: 8, dayEndHour: 18, scheduleEndHour: 18)
        let tenThirty = date(hour: 10, minute: 30)

        let yPosition = scale.yPosition(for: tenThirty)
        let restored = scale.date(fromYOffset: yPosition)

        #expect(yPosition == 225)
        #expect(restored == tenThirty)
    }

    @Test func heightConvertsDurationToPixels() {
        let scale = scale()

        #expect(scale.height(from: date(hour: 9), to: date(hour: 10, minute: 30)) == 135)
    }

    @Test func snapUsesFiveMinuteInterval() {
        let scale = scale()

        #expect(scale.snapToInterval(date(hour: 9, minute: 2)) == date(hour: 9))
        #expect(scale.snapToInterval(date(hour: 9, minute: 3)) == date(hour: 9, minute: 5))
    }

    @Test func formatsHoursAndRangesDeterministically() {
        let scale = scale()
        let formatter = fixedFormatter()

        #expect(scale.formattedHour(13, uses12HourClock: true, formatter: formatter) == "1 PM")
        #expect(scale.formattedHour(25, uses12HourClock: false, formatter: formatter) == "01:00")
        #expect(scale.timeRangeString(start: date(hour: 9), end: date(hour: 10, minute: 30), formatter: formatter) == "09:00 - 10:30")
        #expect(scale.startAndDurationString(start: date(hour: 9), end: date(hour: 10, minute: 30), formatter: formatter) == "09:00 - 10:30 • 90 min")
    }

    @Test func effectiveNowTimeUsesSelectedDateOverride() {
        let scale = scale()
        let currentTime = date(hour: 14)

        #expect(scale.effectiveNowTime(
            currentTime: currentTime,
            overrideEnabled: true,
            overrideHour: 10,
            overrideMinute: 45
        ) == date(hour: 10, minute: 45))

        #expect(scale.effectiveNowTime(
            currentTime: currentTime,
            overrideEnabled: false,
            overrideHour: 10,
            overrideMinute: 45
        ) == currentTime)
    }

    @Test func currentTimeIndicatorSupportsExtendedYesterdayWindow() {
        let selectedDate = date(year: 2026, month: 1, day: 13, hour: 0)
        let nextDayEarly = date(year: 2026, month: 1, day: 14, hour: 1)
        let nextDayLate = date(year: 2026, month: 1, day: 14, hour: 4)
        let scale = TimelineTimeScale(
            selectedDate: selectedDate,
            hourHeight: 90,
            hideNightHours: false,
            dayStartHour: 8,
            dayEndHour: 18,
            scheduleEndHour: 26,
            calendar: testCalendar
        )

        #expect(scale.shouldShowCurrentTimeIndicator(currentDate: nextDayEarly, overrideEnabled: false))
        #expect(!scale.shouldShowCurrentTimeIndicator(currentDate: nextDayLate, overrideEnabled: false))
        #expect(scale.shouldShowCurrentTimeIndicator(currentDate: nextDayLate, overrideEnabled: true))
    }

    private func scale(
        hideNightHours: Bool = false,
        dayStartHour: Int = 8,
        dayEndHour: Int = 18,
        scheduleEndHour: Int = 24
    ) -> TimelineTimeScale {
        TimelineTimeScale(
            selectedDate: date(hour: 0),
            hourHeight: 90,
            hideNightHours: hideNightHours,
            dayStartHour: dayStartHour,
            dayEndHour: dayEndHour,
            scheduleEndHour: scheduleEndHour,
            calendar: testCalendar
        )
    }

    private func fixedFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = testCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        date(year: 2026, month: 6, day: 13, hour: hour, minute: minute)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
