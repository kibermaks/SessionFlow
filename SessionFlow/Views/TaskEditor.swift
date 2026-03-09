import SwiftUI
import AppKit
import Combine

class TaskEditorAction: ObservableObject {
    let moveUp = PassthroughSubject<Void, Never>()
    let moveDown = PassthroughSubject<Void, Never>()
}

struct TaskEditor: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @ObservedObject var action: TaskEditorAction
    
    var body: some View {
        TaskEditorInternal(text: $text, isFocused: $isFocused, moveUpTrigger: action.moveUp, moveDownTrigger: action.moveDown)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
    }
}

struct TaskEditorInternal: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let moveUpTrigger: PassthroughSubject<Void, Never>
    let moveDownTrigger: PassthroughSubject<Void, Never>
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let textView = TaskTextView()
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        textView.onMoveUp = { moveLine(textView: textView, direction: -1) }
        textView.onMoveDown = { moveLine(textView: textView, direction: 1) }
        
        scrollView.documentView = textView
        
        context.coordinator.cancellables.append(moveUpTrigger.sink {
            moveLine(textView: textView, direction: -1)
        })
        context.coordinator.cancellables.append(moveDownTrigger.sink {
            moveLine(textView: textView, direction: 1)
        })
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TaskTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskEditorInternal
        var cancellables = [AnyCancellable]()
        
        init(_ parent: TaskEditorInternal) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? TaskTextView else { return }
            parent.text = textView.string
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }
        
        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }
    
    private func moveLine(textView: NSTextView, direction: Int) {
        let string = textView.string
        let selectedRange = textView.selectedRange()
        
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: selectedRange)
        
        // Find indices of all lines
        _ = []
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length), options: .byLines) { _, range, _, _ in
            // lineRange(for:) is more accurate for empty lines at the end, etc.
            // But enumerateSubstrings byLines is cleaner for standard lines.
            // Let's use a manual scan to include the actual line breaks.
        }
        
        // Manual scan for line ranges including terminators
        var ranges: [NSRange] = []
        var location = 0
        while location < nsString.length {
            let r = nsString.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(r)
            location = r.location + r.length
        }
        
        // Find current line index
        guard let currentIndex = ranges.firstIndex(where: { NSIntersectionRange($0, lineRange).length > 0 || $0.contains(lineRange.location) }) else { return }
        
        let targetIndex = currentIndex + direction
        if targetIndex < 0 || targetIndex >= ranges.count { return }
        
        _ = ranges.map { nsString.substring(with: $0) }
        
        // Ensure the line being moved to the end (if it was the previous last line without a newline) 
        // OR the line being moved FROM the end gets a newline if needed.
        
        // Robust way: strip all line endings, then re-join with \n.
        var lineContents = ranges.map { (nsString.substring(with: $0) as String).trimmingCharacters(in: .newlines) }
        
        let movedLine = lineContents.remove(at: currentIndex)
        lineContents.insert(movedLine, at: targetIndex)
        
        let finalString = lineContents.joined(separator: "\n")
        
        self.text = finalString
        textView.string = finalString
        
        // Restore cursor position to the beginning of the moved line
        let newRanges = calculateLineRanges(finalString as NSString)
        if targetIndex < newRanges.count {
            textView.setSelectedRange(NSRange(location: newRanges[targetIndex].location, length: 0))
        }
    }
    
    private func calculateLineRanges(_ nsString: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        while location < nsString.length {
            let r = nsString.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(r)
            location = r.location + r.length
        }
        if nsString.length > 0 && (nsString.substring(from: nsString.length - 1) == "\n" || nsString.substring(from: nsString.length - 1) == "\r") {
             // If ends with newline, lineRange marks a new empty line at the end
             // But usually it's already handled by lineRange.
        }
        return ranges
    }
}

class TaskTextView: NSTextView {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let controlAndCommand = modifierFlags.contains([.control, .command])
        
        if controlAndCommand {
            if event.keyCode == 126 { // Up arrow
                onMoveUp?()
                return
            } else if event.keyCode == 125 { // Down arrow
                onMoveDown?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
