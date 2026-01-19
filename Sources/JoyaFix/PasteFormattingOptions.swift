import Foundation

/// Represents different formatting options for pasting clipboard items
enum PasteFormattingOption {
    case normal              // Default: preserve formatting
    case plainText          // Strip all formatting (existing behavior)
    case markdown           // Convert HTML to Markdown
    case code               // Escape as code
    case removeLineBreaks   // Merge lines
    case trimWhitespace     // Clean extra spaces
    
    /// Returns the formatted text based on the option
    static func format(_ text: String, option: PasteFormattingOption, htmlData: Data? = nil) -> String {
        switch option {
        case .normal:
            return text
            
        case .plainText:
            // Strip HTML/RTF tags if present
            return stripFormatting(text)
            
        case .markdown:
            // Convert HTML to Markdown if HTML data is available
            if let htmlData = htmlData, let htmlString = String(data: htmlData, encoding: .utf8) {
                return htmlToMarkdown(htmlString)
            }
            // Fallback: try to extract from text if it contains HTML
            if text.contains("<") && text.contains(">") {
                return htmlToMarkdown(text)
            }
            return text
            
        case .code:
            // Escape special characters for code
            return escapeAsCode(text)
            
        case .removeLineBreaks:
            // Replace line breaks with spaces
            return text.replacingOccurrences(of: "\n", with: " ")
                       .replacingOccurrences(of: "\r", with: " ")
                       .replacingOccurrences(of: "\r\n", with: " ")
            
        case .trimWhitespace:
            // Trim leading/trailing whitespace and collapse multiple spaces
            return trimAndCollapseWhitespace(text)
        }
    }
    
    // MARK: - Formatting Functions
    
    /// Strips HTML and RTF formatting tags
    private static func stripFormatting(_ text: String) -> String {
        var result = text
        
        // Remove HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Decode HTML entities
        result = decodeHTMLEntities(result)
        
        // Remove RTF control words (basic cleanup)
        result = result.replacingOccurrences(of: "\\\\[a-z]+[0-9]*", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Converts HTML to Markdown (basic conversion)
    private static func htmlToMarkdown(_ html: String) -> String {
        var markdown = html
        
        // Remove script and style tags with their content
        if let scriptRegex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsString = markdown as NSString
            let range = NSRange(location: 0, length: nsString.length)
            markdown = scriptRegex.stringByReplacingMatches(in: markdown, options: [], range: range, withTemplate: "")
        }
        if let styleRegex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsString = markdown as NSString
            let range = NSRange(location: 0, length: nsString.length)
            markdown = styleRegex.stringByReplacingMatches(in: markdown, options: [], range: range, withTemplate: "")
        }
        
        // Headers
        markdown = markdown.replacingOccurrences(of: "<h1[^>]*>", with: "# ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<h2[^>]*>", with: "## ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<h3[^>]*>", with: "### ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<h4[^>]*>", with: "#### ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<h5[^>]*>", with: "##### ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<h6[^>]*>", with: "###### ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: .regularExpression)
        
        // Bold
        markdown = markdown.replacingOccurrences(of: "<strong[^>]*>", with: "**", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<b[^>]*>", with: "**", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</strong>", with: "**", options: .caseInsensitive)
        markdown = markdown.replacingOccurrences(of: "</b>", with: "**", options: .caseInsensitive)
        
        // Italic
        markdown = markdown.replacingOccurrences(of: "<em[^>]*>", with: "*", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<i[^>]*>", with: "*", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</em>", with: "*", options: .caseInsensitive)
        markdown = markdown.replacingOccurrences(of: "</i>", with: "*", options: .caseInsensitive)
        
        // Links
        markdown = markdown.replacingOccurrences(
            of: "<a[^>]*href=\"([^\"]+)\"[^>]*>([^<]+)</a>",
            with: "[$2]($1)",
            options: .regularExpression
        )
        
        // Images
        markdown = markdown.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]+)\"[^>]*alt=\"([^\"]+)\"[^>]*>",
            with: "![$2]($1)",
            options: .regularExpression
        )
        markdown = markdown.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]+)\"[^>]*>",
            with: "![]($1)",
            options: .regularExpression
        )
        
        // Code blocks
        markdown = markdown.replacingOccurrences(of: "<pre[^>]*>", with: "```\n", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</pre>", with: "\n```", options: .caseInsensitive)
        markdown = markdown.replacingOccurrences(of: "<code[^>]*>", with: "`", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</code>", with: "`", options: .caseInsensitive)
        
        // Lists
        markdown = markdown.replacingOccurrences(of: "<ul[^>]*>", with: "\n", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</ul>", with: "\n", options: .caseInsensitive)
        markdown = markdown.replacingOccurrences(of: "<ol[^>]*>", with: "\n", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</ol>", with: "\n", options: .caseInsensitive)
        markdown = markdown.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        
        // Line breaks
        markdown = markdown.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<p[^>]*>", with: "\n", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        
        // Remove all remaining HTML tags
        markdown = markdown.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Decode HTML entities
        markdown = decodeHTMLEntities(markdown)
        
        // Clean up extra whitespace
        markdown = markdown.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return markdown
    }
    
    /// Escapes text as code (for code blocks)
    private static func escapeAsCode(_ text: String) -> String {
        var result = text
        
        // Escape backticks (common in code)
        result = result.replacingOccurrences(of: "`", with: "\\`")
        
        // Escape dollar signs (for shell scripts)
        result = result.replacingOccurrences(of: "$", with: "\\$")
        
        // Escape backslashes (but not already escaped ones)
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\\\\\\", with: "\\\\") // Fix double escaping
        
        return result
    }
    
    /// Trims whitespace and collapses multiple spaces
    private static func trimAndCollapseWhitespace(_ text: String) -> String {
        var result = text
        
        // Trim leading and trailing whitespace from each line
        let lines = result.components(separatedBy: .newlines)
        result = lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        
        // Collapse multiple spaces to single space (but preserve line breaks)
        result = result.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        
        // Remove empty lines (optional - could be made configurable)
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Decodes common HTML entities
    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        
        // Common HTML entities
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…"
        ]
        
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Decode numeric entities (basic support)
        let numericEntityPattern = "&#([0-9]+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            let nsString = result as NSString
            let range = NSRange(location: 0, length: nsString.length)
            var matches: [(NSRange, String)] = []
            
            regex.enumerateMatches(in: result, options: [], range: range) { match, _, _ in
                guard let match = match, match.numberOfRanges > 1,
                      let numberRange = Range(match.range(at: 1), in: result),
                      let code = Int(result[numberRange]) else { return }
                
                if let scalar = UnicodeScalar(code) {
                    matches.append((match.range, String(Character(scalar))))
                }
            }
            
            // Replace in reverse order to maintain indices
            for (range, replacement) in matches.reversed() {
                result = (result as NSString).replacingCharacters(in: range, with: replacement)
            }
        }
        
        return result
    }
}

