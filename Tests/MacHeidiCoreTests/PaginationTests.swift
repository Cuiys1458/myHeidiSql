import Testing
@testable import MacHeidiCore

@Suite("Pagination S5D")
struct PaginationTests {

    // MARK: totalPages

    @Test("Empty table → 1 page (display sane)")
    func emptyIsOnePage() {
        let p = Pagination(total: 0, pageSize: 100, currentPage: 1)
        #expect(p.totalPages == 1)
    }

    @Test("Exact multiple → divides cleanly")
    func exactMultiple() {
        let p = Pagination(total: 5000, pageSize: 100, currentPage: 1)
        #expect(p.totalPages == 50)
    }

    @Test("Inexact multiple rounds up")
    func roundsUp() {
        let p = Pagination(total: 251, pageSize: 100, currentPage: 1)
        #expect(p.totalPages == 3)
    }

    @Test("Single overflow row")
    func singleOverflow() {
        let p = Pagination(total: 101, pageSize: 100, currentPage: 1)
        #expect(p.totalPages == 2)
    }

    // MARK: offset

    @Test("Page 1 offset is 0")
    func page1Offset() {
        let p = Pagination(total: 5000, pageSize: 100, currentPage: 1)
        #expect(p.offset == 0)
    }

    @Test("Page 3 offset is (3-1)*100 = 200")
    func page3Offset() {
        let p = Pagination(total: 5000, pageSize: 100, currentPage: 3)
        #expect(p.offset == 200)
    }

    @Test("PageSize 500, page 4 → offset 1500")
    func biggerPageSize() {
        let p = Pagination(total: 10000, pageSize: 500, currentPage: 4)
        #expect(p.offset == 1500)
    }

    // MARK: navigation flags

    @Test("On first page: cannot go first/prev, can next/last")
    func firstPage() {
        let p = Pagination(total: 5000, pageSize: 100, currentPage: 1)
        #expect(!p.canGoFirst)
        #expect(!p.canGoPrev)
        #expect(p.canGoNext)
        #expect(p.canGoLast)
    }

    @Test("On last page: cannot go next/last, can first/prev")
    func lastPage() {
        let p = Pagination(total: 5000, pageSize: 100, currentPage: 50)
        #expect(p.canGoFirst)
        #expect(p.canGoPrev)
        #expect(!p.canGoNext)
        #expect(!p.canGoLast)
    }

    @Test("Single page: nothing is enabled")
    func singlePage() {
        let p = Pagination(total: 50, pageSize: 100, currentPage: 1)
        #expect(!p.canGoFirst)
        #expect(!p.canGoPrev)
        #expect(!p.canGoNext)
        #expect(!p.canGoLast)
    }

    // MARK: clamping

    @Test("currentPage clamped if greater than total")
    func clampOverflow() {
        let p = Pagination(total: 250, pageSize: 100, currentPage: 99)
        #expect(p.currentPage == 3)
    }

    @Test("currentPage clamped to 1 if less")
    func clampUnderflow() {
        let p = Pagination(total: 250, pageSize: 100, currentPage: 0)
        #expect(p.currentPage == 1)
    }

    @Test("withPageSize: changing page size clamps current page")
    func resizeReclamps() {
        var p = Pagination(total: 250, pageSize: 100, currentPage: 3)
        p = p.withPageSize(500)
        #expect(p.totalPages == 1)
        #expect(p.currentPage == 1)
    }

    @Test("withTotal: total drops to 0 → page = 1")
    func totalToZero() {
        var p = Pagination(total: 250, pageSize: 100, currentPage: 3)
        p = p.withTotal(0)
        #expect(p.currentPage == 1)
        #expect(p.totalPages == 1)
    }

    // MARK: missing total fallback

    @Test("Unknown total: navigation allows forward; totalPages is nil")
    func unknownTotal() {
        let p = Pagination(total: nil, pageSize: 100, currentPage: 5)
        #expect(p.totalPages == nil)
        #expect(p.canGoNext)         // 不知道是否到底，允许尝试
        #expect(p.canGoPrev)         // page 5 可以回退
        #expect(!p.canGoLast)        // 不知道末页在哪
    }

    @Test("Unknown total + page 1: canGoPrev = false, canGoNext = true")
    func unknownTotalFirstPage() {
        let p = Pagination(total: nil, pageSize: 100, currentPage: 1)
        #expect(!p.canGoPrev)
        #expect(p.canGoNext)
    }
}
