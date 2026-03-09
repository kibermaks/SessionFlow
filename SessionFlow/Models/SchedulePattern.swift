import Foundation

// MARK: - Schedule Pattern
enum SchedulePattern: String, Codable, CaseIterable, Identifiable {
    case alternating = "Alternating"
    case alternatingReverse = "Alternating Reverse"
    case allWorkFirst = "All Work First"
    case allSideFirst = "All Side First"
    case sidesFirstAndLast = "Sides First & Last"
    case customRatio = "Custom Ratio"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .alternating:
            return "Work first, then Side (e.g., W→W→S→W→W→S)"
        case .alternatingReverse:
            return "Side first, then Work (e.g., S→W→W→S→W→W)"
        case .allWorkFirst:
            return "Schedules all Work sessions first, then Side sessions"
        case .allSideFirst:
            return "Schedules all Side sessions first, then Work sessions"
        case .customRatio:
            return "Custom pattern with configurable Work:Side ratio"
        case .sidesFirstAndLast:
            return "Sides at the beginning and end, with all Work sessions in between"
        }
    }
    
    var icon: String {
        switch self {
        case .alternating: return "arrow.right"
        case .alternatingReverse: return "arrow.left"
        case .allWorkFirst: return "arrow.right.to.line"
        case .allSideFirst: return "arrow.left.to.line"
        case .customRatio: return "slider.horizontal.3"
        case .sidesFirstAndLast: return "arrow.left.and.right"
        }
    }
}

// MARK: - Session Order Generator
struct SessionOrderGenerator {
    let pattern: SchedulePattern
    let workSessions: Int
    let sideSessions: Int
    let workSessionsPerCycle: Int // For alternating/custom pattern
    let sideSessionsPerCycle: Int // For custom pattern
    let sideFirst: Bool // For custom pattern (default false)
    
    /// Generates the order of session types based on the pattern
    func generateOrder() -> [SessionType] {
        var order: [SessionType] = []
        
        switch pattern {
        case .allWorkFirst:
            // All work sessions, then all side sessions
            order.append(contentsOf: Array(repeating: .work, count: workSessions))
            order.append(contentsOf: Array(repeating: .side, count: sideSessions))
            
        case .allSideFirst:
            // All side sessions, then all work sessions
            order.append(contentsOf: Array(repeating: .side, count: sideSessions))
            order.append(contentsOf: Array(repeating: .work, count: workSessions))
            
        case .alternating:
            // Alternating: N work sessions, then 1 side session
            var remainingWork = workSessions
            var remainingSide = sideSessions
            var workInCurrentCycle = 0
            
            while remainingWork > 0 || remainingSide > 0 {
                // Add work sessions up to the cycle limit
                if workInCurrentCycle < workSessionsPerCycle && remainingWork > 0 {
                    order.append(.work)
                    remainingWork -= 1
                    workInCurrentCycle += 1
                } else if remainingSide > 0 {
                    // Add a side session and reset cycle
                    order.append(.side)
                    remainingSide -= 1
                    workInCurrentCycle = 0
                } else if remainingWork > 0 {
                    // No more side sessions, add remaining work
                    order.append(.work)
                    remainingWork -= 1
                }
            }
            
        case .customRatio:
            // Custom Ratio: X work sessions, Y side sessions per cycle
            // Order depends on sideFirst flag
            var remainingWork = workSessions
            var remainingSide = sideSessions
            var workInCurrentCycle = 0
            var sideInCurrentCycle = 0
            
            // Start with Work unless Side First is enabled
            var isWorkTurn = !sideFirst
            
            while remainingWork > 0 || remainingSide > 0 {
                if isWorkTurn {
                    if workInCurrentCycle < workSessionsPerCycle && remainingWork > 0 {
                        order.append(.work)
                        remainingWork -= 1
                        workInCurrentCycle += 1
                    } else {
                        // Switch to Side
                        isWorkTurn = false
                        workInCurrentCycle = 0
                        
                        // If we have no side sessions left, check if we need to switch back immediately
                        if remainingSide == 0 && remainingWork > 0 {
                            isWorkTurn = true
                        }
                    }
                } else {
                    if sideInCurrentCycle < sideSessionsPerCycle && remainingSide > 0 {
                        order.append(.side)
                        remainingSide -= 1
                        sideInCurrentCycle += 1
                    } else {
                        // Switch to Work
                        isWorkTurn = true
                        sideInCurrentCycle = 0
                        
                        // If we have no work sessions left, switch back immediately
                        if remainingWork == 0 && remainingSide > 0 {
                            isWorkTurn = false
                        }
                    }
                }
            }
            
        case .alternatingReverse:
            // Alternating Reverse: 1 side session, then N work sessions (S→W→W→S→W→W)
            // It should respect Work Sessions Per Cycle
            var remainingWork = workSessions
            var remainingSide = sideSessions
            var workInCurrentCycle = 0
            var needSideFirst = true // Start with a side session
            
            while remainingWork > 0 || remainingSide > 0 {
                if needSideFirst && remainingSide > 0 {
                    // Add one side session at start of cycle
                    order.append(.side)
                    remainingSide -= 1
                    needSideFirst = false
                    workInCurrentCycle = 0
                } else if workInCurrentCycle < workSessionsPerCycle && remainingWork > 0 {
                    // Add work sessions up to the cycle limit
                    order.append(.work)
                    remainingWork -= 1
                    workInCurrentCycle += 1
                } else if remainingSide > 0 {
                    // Cycle complete, add side and restart
                    // Logic check: if we just finished N work sessions, we need a Side session now.
                    // The 'needSideFirst' flag handles the FIRST side session.
                    // Subsequent ones are handled here.
                    order.append(.side)
                    remainingSide -= 1
                    workInCurrentCycle = 0
                } else if remainingWork > 0 {
                    // No more side sessions, add remaining work
                    order.append(.work)
                    remainingWork -= 1
                }
            }
            
        case .sidesFirstAndLast:
            // Sides First & Last: Put up to sideSessionsPerCycle at the beginning,
            // then all work sessions, then remaining side sessions
            var remainingWork = workSessions
            var remainingSide = sideSessions
            
            // Add initial side sessions (up to sideSessionsPerCycle)
            let initialSides = min(sideSessionsPerCycle, remainingSide)
            order.append(contentsOf: Array(repeating: .side, count: initialSides))
            remainingSide -= initialSides
            
            // Add all work sessions
            order.append(contentsOf: Array(repeating: .work, count: remainingWork))
            remainingWork = 0
            
            // Add remaining side sessions
            order.append(contentsOf: Array(repeating: .side, count: remainingSide))
        }
        
        return order
    }
}
