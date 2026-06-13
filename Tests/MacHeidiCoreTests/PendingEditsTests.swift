import Testing
@testable import MacHeidiCore

@Suite("PendingEdits S3.5 dirty tracking")
struct PendingEditsTests {

    private let cols = [
        ColumnMeta.int(name: "id", nullable: false),
        ColumnMeta.varchar(name: "name", nullable: false),
        ColumnMeta.int(name: "age", nullable: true),
    ]

    // MARK: dirty marking

    @Test("Edit a cell marks the row dirty")
    func editMarksDirty() {
        var edits = PendingEdits()
        edits.editCell(rowId: "r1", originalValues: [.int(1), .string("Alice"), .int(30)],
                       columnIndex: 1, newValue: .string("Bob"), columns: cols)
        #expect(edits.isDirty(rowId: "r1"))
        #expect(edits.dirtyCellCount == 1)
    }

    @Test("Editing back to original clears dirty")
    func editBackClearsDirty() {
        var edits = PendingEdits()
        edits.editCell(rowId: "r1", originalValues: [.int(1), .string("Alice"), .int(30)],
                       columnIndex: 1, newValue: .string("Bob"), columns: cols)
        edits.editCell(rowId: "r1", originalValues: [.int(1), .string("Alice"), .int(30)],
                       columnIndex: 1, newValue: .string("Alice"), columns: cols)
        #expect(!edits.isDirty(rowId: "r1"))
        #expect(edits.dirtyCellCount == 0)
    }

    @Test("Two columns tracked independently")
    func twoColumns() {
        var edits = PendingEdits()
        let orig: [CellValue] = [.int(1), .string("Alice"), .int(30)]
        edits.editCell(rowId: "r1", originalValues: orig, columnIndex: 1, newValue: .string("Bob"), columns: cols)
        edits.editCell(rowId: "r1", originalValues: orig, columnIndex: 2, newValue: .int(31), columns: cols)
        #expect(edits.dirtyCellCount == 2)
    }

    @Test("Discard clears all")
    func discard() {
        var edits = PendingEdits()
        let orig: [CellValue] = [.int(1), .string("Alice"), .int(30)]
        edits.editCell(rowId: "r1", originalValues: orig, columnIndex: 1, newValue: .string("Bob"), columns: cols)
        edits.markRowDelete(rowId: "r2")
        edits.discard()
        #expect(edits.dirtyCellCount == 0)
        #expect(!edits.isMarkedForDeletion(rowId: "r2"))
    }

    // MARK: deletion

    @Test("Mark row for delete")
    func markDelete() {
        var edits = PendingEdits()
        edits.markRowDelete(rowId: "r1")
        #expect(edits.isMarkedForDeletion(rowId: "r1"))
    }

    @Test("Unmark deletion")
    func unmarkDelete() {
        var edits = PendingEdits()
        edits.markRowDelete(rowId: "r1")
        edits.unmarkRowDelete(rowId: "r1")
        #expect(!edits.isMarkedForDeletion(rowId: "r1"))
    }

    // MARK: insert

    @Test("Insert new row")
    func insertRow() {
        var edits = PendingEdits()
        let id = edits.addNewRow(initialValues: [:])
        #expect(edits.pendingInserts.contains { $0.localId == id })
    }

    @Test("Empty insert (no values touched) is filtered out by isMeaningful")
    func emptyInsert() {
        var edits = PendingEdits()
        let id = edits.addNewRow(initialValues: [:])
        let row = edits.pendingInserts.first { $0.localId == id }!
        #expect(!row.hasUserSetValues)
    }
}
