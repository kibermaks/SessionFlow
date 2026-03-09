import Foundation

// MARK: - Availability Calculator
/// Calculates available time slots and session possibilities
struct AvailabilityCalculator {
    // MARK: - Time Gap
    struct TimeGap: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        
        var duration: TimeInterval {
            end.timeIntervalSince(start)
        }
        
        var durationMinutes: Int {
            Int(duration / 60)
        }
    }
    
    // MARK: - Availability Summary
    struct AvailabilitySummary {
        let totalAvailableMinutes: Int
        let gaps: [TimeGap]
        let possibleWorkSessions: Int
        let possibleSideSessions: Int
        let maxPossibleSessions: Int
        let longestGapMinutes: Int
        
        var totalAvailableHours: Double {
            Double(totalAvailableMinutes) / 60.0
        }
        
        var formattedAvailableTime: String {
            let hours = totalAvailableMinutes / 60
            let mins = totalAvailableMinutes % 60
            if hours > 0 {
                return "\(hours)h \(mins)m"
            }
            return "\(mins)m"
        }
    }
    
    // MARK: - Calculate Availability
    
    static func calculate(
        startTime: Date,
        endTime: Date,
        busySlots: [BusyTimeSlot],
        bufferMinutes: Int,
        workSessionDuration: Int,
        sideSessionDuration: Int,
        restDuration: Int
    ) -> AvailabilitySummary {
        let bufferDuration = TimeInterval(bufferMinutes * 60)
        
        // Sort busy slots by start time
        let sortedSlots = busySlots.sorted { $0.startTime < $1.startTime }
        
        var gaps: [TimeGap] = []
        var currentTime = startTime
        
        for slot in sortedSlots {
            let effectiveStart = slot.startTime.addingTimeInterval(-bufferDuration)
            let effectiveEnd = slot.endTime.addingTimeInterval(bufferDuration)
            
            // Check if there's a gap before this event
            if currentTime < effectiveStart && effectiveStart < endTime {
                let gapEnd = min(effectiveStart, endTime)
                if gapEnd > currentTime {
                    gaps.append(TimeGap(start: currentTime, end: gapEnd))
                }
            }
            
            // Move past this event
            if effectiveEnd > currentTime {
                currentTime = effectiveEnd
            }
        }
        
        // Add remaining time until end of day
        if currentTime < endTime {
            gaps.append(TimeGap(start: currentTime, end: endTime))
        }
        
        // Calculate totals
        let totalMinutes = gaps.reduce(0) { $0 + $1.durationMinutes }
        let longestGap = gaps.max(by: { $0.durationMinutes < $1.durationMinutes })?.durationMinutes ?? 0
        
        // Calculate possible sessions (accounting for rest)
        let workWithRest = workSessionDuration + restDuration
        let sideWithRest = sideSessionDuration + restDuration
        
        // Count sessions that fit in each gap
        var possibleWork = 0
        var possibleSide = 0
        
        for gap in gaps {
            possibleWork += gap.durationMinutes / workWithRest
            possibleSide += gap.durationMinutes / sideWithRest
        }
        
        return AvailabilitySummary(
            totalAvailableMinutes: totalMinutes,
            gaps: gaps,
            possibleWorkSessions: possibleWork,
            possibleSideSessions: possibleSide,
            maxPossibleSessions: max(possibleWork, possibleSide),
            longestGapMinutes: longestGap
        )
    }
    
    // MARK: - Quick Check
    
    static func canFitSession(
        duration: Int,
        at time: Date,
        endTime: Date,
        busySlots: [BusyTimeSlot],
        bufferMinutes: Int
    ) -> Bool {
        let sessionEnd = time.addingTimeInterval(TimeInterval(duration * 60))
        
        guard sessionEnd <= endTime else { return false }
        
        let bufferDuration = TimeInterval(bufferMinutes * 60)
        
        for slot in busySlots {
            let effectiveStart = slot.startTime.addingTimeInterval(-bufferDuration)
            let effectiveEnd = slot.endTime.addingTimeInterval(bufferDuration)
            
            // Check for overlap
            if time < effectiveEnd && sessionEnd > effectiveStart {
                return false
            }
        }
        
        return true
    }
}
