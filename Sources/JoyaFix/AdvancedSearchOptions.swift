import Foundation

/// Represents advanced search options for clipboard history
struct AdvancedSearchOptions {
    var searchText: String = ""
    var useRegex: Bool = false
    var dateRange: DateRangeFilter = .all
    var customDateRange: CustomDateRange? = nil
    var contentTypes: Set<ContentTypeFilter> = []
    var booleanOperator: BooleanOperator = .and
    
    /// Applies all filters to a list of clipboard items
    func filter(_ items: [ClipboardItem]) -> [ClipboardItem] {
        var filtered = items
        
        // Date range filter
        if dateRange != .all {
            let now = Date()
            let calendar = Calendar.current
            let startDate: Date
            
            switch dateRange {
            case .all:
                return filtered // Shouldn't reach here, but just in case
            case .today:
                startDate = calendar.startOfDay(for: now)
            case .lastWeek:
                startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            case .lastMonth:
                startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            case .lastYear:
                startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            case .custom:
                if let customRange = customDateRange {
                    filtered = filtered.filter { item in
                        item.timestamp >= customRange.startDate && item.timestamp <= customRange.endDate
                    }
                }
                // Continue with other filters
                return applyContentAndTextFilters(to: filtered)
            }
            
            filtered = filtered.filter { item in
                item.timestamp >= startDate
            }
        }
        
        // Content type filter
        if !contentTypes.isEmpty {
            filtered = filtered.filter { item in
                contentTypes.contains { contentType in
                    switch contentType {
                    case .images:
                        return item.isImage
                    case .urls:
                        return item.plainTextPreview.hasPrefix("http://") || item.plainTextPreview.hasPrefix("https://")
                    case .code:
                        return isCodeContent(item.plainTextPreview)
                    case .text:
                        return !item.isImage && !isURL(item.plainTextPreview) && !isCodeContent(item.plainTextPreview)
                    case .richText:
                        return item.hasRichFormatting
                    }
                }
            }
        }
        
        // Text search filter (regex or fuzzy)
        return applyContentAndTextFilters(to: filtered)
    }
    
    private func applyContentAndTextFilters(to items: [ClipboardItem]) -> [ClipboardItem] {
        guard !searchText.isEmpty else { return items }
        
        if useRegex {
            return filterWithRegex(items)
        } else {
            return filterWithFuzzySearch(items)
        }
    }
    
    private func filterWithRegex(_ items: [ClipboardItem]) -> [ClipboardItem] {
        guard let regex = try? NSRegularExpression(pattern: searchText, options: [.caseInsensitive]) else {
            // Invalid regex - return empty or fallback to fuzzy
            return []
        }
        
        return items.filter { item in
            let text = item.textForPasting
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }
    
    private func filterWithFuzzySearch(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let threshold = 0.3
        return items.filter { item in
            let score = item.plainTextPreview.fuzzyScore(word: searchText)
            return score >= threshold
        }.sorted { item1, item2 in
            let score1 = item1.plainTextPreview.fuzzyScore(word: searchText)
            let score2 = item2.plainTextPreview.fuzzyScore(word: searchText)
            return score1 > score2
        }
    }
    
    // MARK: - Helper Functions
    
    private func isURL(_ text: String) -> Bool {
        return text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("ftp://")
    }
    
    private func isCodeContent(_ text: String) -> Bool {
        // Detect code patterns
        let codeIndicators = [
            "function ", "def ", "class ", "import ", "from ", "const ", "let ", "var ",
            "public ", "private ", "protected ", "static ", "async ", "await ",
            "#include", "#define", "<?php", "<?xml", "<!DOCTYPE",
            "SELECT ", "INSERT ", "UPDATE ", "DELETE ", "CREATE ", "ALTER ",
            "{", "}", "()", "=>", "->", "::", "&&", "||", "===", "!=="
        ]
        
        // Check if text contains multiple code indicators
        var indicatorCount = 0
        for indicator in codeIndicators {
            if text.contains(indicator) {
                indicatorCount += 1
                if indicatorCount >= 2 {
                    return true
                }
            }
        }
        
        // Also check for common code file extensions in text
        let codeExtensions = [".swift", ".py", ".js", ".ts", ".java", ".cpp", ".c", ".h", ".php", ".rb", ".go"]
        return codeExtensions.contains { text.contains($0) }
    }
}

// MARK: - Date Range Filter

enum DateRangeFilter: String, CaseIterable, Identifiable {
    case all = "All Time"
    case today = "Today"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case lastYear = "Last Year"
    case custom = "Custom Range"
    
    var id: String { rawValue }
    
    var startDate: Date? {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .all:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .custom:
            return nil // Requires explicit start/end dates
        }
    }
    
    var endDate: Date? {
        switch self {
        case .all, .custom:
            return nil
        default:
            return Date()
        }
    }
}

// MARK: - Content Type Filter

enum ContentTypeFilter: String, CaseIterable, Identifiable {
    case images = "Images"
    case urls = "URLs"
    case code = "Code"
    case text = "Text"
    case richText = "Rich Text"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .images: return "photo"
        case .urls: return "link"
        case .code: return "curlybraces"
        case .text: return "text.alignleft"
        case .richText: return "doc.richtext"
        }
    }
}

// MARK: - Boolean Operator

enum BooleanOperator: String, CaseIterable, Identifiable {
    case and = "AND"
    case or = "OR"
    case not = "NOT"
    
    var id: String { rawValue }
}

// MARK: - Custom Date Range

struct CustomDateRange {
    let startDate: Date
    let endDate: Date
    
    init(start: Date, end: Date) {
        self.startDate = start
        self.endDate = end
    }
}

// Extend DateRangeFilter to support custom ranges
extension DateRangeFilter {
    static func custom(start: Date, end: Date) -> DateRangeFilter {
        return .custom
    }
}
