import Foundation

/// 表数据浏览的分页状态（PRD §5.3.5）。
///
/// 不可变值类型；翻页 / 改页大小 / 总数变更都返回新实例，确保 ViewModel 状态可追踪。
public struct Pagination: Equatable, Sendable {

    /// 总行数。`nil` 表示 COUNT(*) 失败；UI 显示 "?"，仍允许 Next。
    public let total: UInt64?
    public let pageSize: Int
    public let currentPage: Int   // 1-based；构造器自动 clamp 到 [1, totalPages]

    public static let defaultPageSize = 100
    public static let allowedPageSizes: [Int] = [100, 500, 1000, 5000]

    public init(total: UInt64?, pageSize: Int, currentPage: Int) {
        let safeSize = max(1, pageSize)
        let pages: Int = {
            guard let t = total else { return Int.max }
            if t == 0 { return 1 }
            return Int((t + UInt64(safeSize) - 1) / UInt64(safeSize))
        }()
        self.total = total
        self.pageSize = safeSize
        // clamp
        if total == nil {
            self.currentPage = max(1, currentPage)
        } else {
            self.currentPage = min(max(1, currentPage), pages)
        }
    }

    /// 总页数。`nil` 表示总数未知。
    public var totalPages: Int? {
        guard let t = total else { return nil }
        if t == 0 { return 1 }
        return Int((t + UInt64(pageSize) - 1) / UInt64(pageSize))
    }

    /// 当前页对应的 SQL `OFFSET` 值。
    public var offset: Int {
        (currentPage - 1) * pageSize
    }

    /// 当前页对应的 SQL `LIMIT` 值（永远等于 pageSize）。
    public var limit: Int { pageSize }

    // MARK: navigation flags

    public var canGoFirst: Bool { currentPage > 1 }
    public var canGoPrev:  Bool { currentPage > 1 }
    public var canGoNext:  Bool {
        if let pages = totalPages { return currentPage < pages }
        return true   // 未知总数：允许尝试
    }
    public var canGoLast:  Bool {
        guard let pages = totalPages else { return false }
        return currentPage < pages
    }

    // MARK: transitions

    public func withPage(_ page: Int) -> Pagination {
        Pagination(total: total, pageSize: pageSize, currentPage: page)
    }
    public func withPageSize(_ size: Int) -> Pagination {
        Pagination(total: total, pageSize: size, currentPage: currentPage)
    }
    public func withTotal(_ newTotal: UInt64?) -> Pagination {
        Pagination(total: newTotal, pageSize: pageSize, currentPage: currentPage)
    }

    public func first() -> Pagination { withPage(1) }
    public func prev()  -> Pagination { withPage(max(1, currentPage - 1)) }
    public func next()  -> Pagination { withPage(currentPage + 1) }
    public func last()  -> Pagination {
        guard let pages = totalPages else { return self }
        return withPage(pages)
    }
}
