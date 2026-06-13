import Testing
@testable import SessionFlow

struct SessionFlowEventSemanticsTests {
    @Test func recognizedOwnershipTagsStayInSessionPriorityOrder() {
        #expect(SessionFlowEventSemantics.recognizedOwnershipTags == [
            "#work",
            "#side",
            "#deep",
            "#plan",
            "#break",
        ])

        #expect(SessionFlowEventSemantics.ownershipTag(for: .work) == .work)
        #expect(SessionFlowEventSemantics.ownershipTag(for: .side) == .side)
        #expect(SessionFlowEventSemantics.ownershipTag(for: .deep) == .deep)
        #expect(SessionFlowEventSemantics.ownershipTag(for: .planning) == .planning)
        #expect(SessionFlowEventSemantics.ownershipTag(for: .bigRest) == .bigRest)
    }

    @Test func sessionTypeFromNotesUsesExactCaseInsensitiveTags() {
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Client delivery #WORK") == .work)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Admin #side") == .side)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Strategy #plan") == .planning)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Long rest #break") == .bigRest)

        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Cardio #workout") == nil)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Roadmap #planned") == nil)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "Admin #side-project") == nil)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "prefix#work") == nil)
    }

    @Test func sessionTypeKeepsExistingPriorityWhenMultipleTagsArePresent() {
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "#deep #work") == .work)
        #expect(SessionFlowEventSemantics.sessionType(fromNotes: "#break #plan") == .planning)
    }

    @Test func ownershipTagsAreReturnedInNoteOrderWithoutDuplicates() {
        let tags = SessionFlowEventSemantics.ownershipTags(
            in: "First #SIDE, then #work, then duplicate #side and rest #break."
        )

        #expect(tags == [.side, .work, .bigRest])
        #expect(SessionFlowEventSemantics.isSessionFlowOwned("External #deep"))
        #expect(!SessionFlowEventSemantics.isSessionFlowOwned("External #deepwork"))
    }

    @Test func strippingOwnershipTagsPreservesOtherSessionFlowMetadata() {
        let notes = """
        Client delivery #work #flowfixed

        #plan
        Wrap up #FLOW✅
        """

        #expect(SessionFlowEventSemantics.strippingOwnershipTags(from: notes) == """
        Client delivery #flowfixed

        Wrap up #FLOW✅
        """)
    }

    @Test func strippingOwnershipTagsReturnsNilWhenOnlyOwnershipTagsRemain() {
        #expect(SessionFlowEventSemantics.strippingOwnershipTags(from: " #work\n#BREAK ") == nil)
        #expect(SessionFlowEventSemantics.strippingOwnershipTags(from: nil) == nil)
        #expect(SessionFlowEventSemantics.strippingOwnershipTags(from: "") == nil)
    }
}
