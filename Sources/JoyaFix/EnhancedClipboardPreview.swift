import SwiftUI
import AppKit

/// Enhanced preview view for clipboard items with syntax highlighting, PDF preview, and table formatting
struct EnhancedClipboardPreview: View {
    let item: ClipboardItem
    @State private var detectedLanguage: CodeLanguage? = nil
    @State private var isTable: Bool = false
    @State private var tableData: [[String]] = []
    
    var body: some View {
        Group {
            if item.isImage {
                ImagePreview(item: item)
            } else if isTable {
                TablePreview(data: tableData)
            } else if let language = detectedLanguage {
                CodePreview(text: item.textForPasting, language: language)
            } else if item.hasRichFormatting {
                RichTextPreview(item: item)
            } else {
                PlainTextPreview(text: item.textForPasting)
            }
        }
        .onAppear {
            detectContentType()
        }
    }
    
    private func detectContentType() {
        let text = item.textForPasting
        
        // Detect code language
        detectedLanguage = detectCodeLanguage(text)
        
        // Detect table format (CSV/TSV)
        if isCSVOrTSV(text) {
            isTable = true
            tableData = parseTable(text)
        }
    }
    
    private func detectCodeLanguage(_ text: String) -> CodeLanguage? {
        // Simple heuristics for language detection
        let swiftKeywords = ["func ", "let ", "var ", "class ", "struct ", "enum ", "import Swift"]
        let pythonKeywords = ["def ", "import ", "from ", "class ", "if __name__"]
        let jsKeywords = ["function ", "const ", "let ", "var ", "=>", "import ", "export "]
        
        let swiftCount = swiftKeywords.filter { text.contains($0) }.count
        let pythonCount = pythonKeywords.filter { text.contains($0) }.count
        let jsCount = jsKeywords.filter { text.contains($0) }.count
        
        if swiftCount >= 2 {
            return .swift
        } else if pythonCount >= 2 {
            return .python
        } else if jsCount >= 2 {
            return .javascript
        }
        
        // Check file extensions in text
        if text.contains(".swift") {
            return .swift
        } else if text.contains(".py") {
            return .python
        } else if text.contains(".js") || text.contains(".ts") {
            return .javascript
        }
        
        return nil
    }
    
    private func isCSVOrTSV(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        
        // Check if lines have consistent delimiter
        let firstLineDelimiters = countDelimiters(lines[0])
        let hasConsistentDelimiters = lines.allSatisfy { countDelimiters($0) == firstLineDelimiters }
        
        return hasConsistentDelimiters && firstLineDelimiters > 0
    }
    
    private func countDelimiters(_ line: String) -> Int {
        let commaCount = line.components(separatedBy: ",").count - 1
        let tabCount = line.components(separatedBy: "\t").count - 1
        return max(commaCount, tabCount)
    }
    
    private func parseTable(_ text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let delimiter = text.contains("\t") ? "\t" : ","
        
        return lines.map { line in
            line.components(separatedBy: delimiter)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}

// MARK: - Code Language

enum CodeLanguage: String {
    case swift = "Swift"
    case python = "Python"
    case javascript = "JavaScript"
    
    var keywords: [String] {
        switch self {
        case .swift:
            return ["func", "let", "var", "class", "struct", "enum", "import", "if", "else", "for", "while", "return", "guard", "switch", "case", "default", "private", "public", "static", "async", "await"]
        case .python:
            return ["def", "class", "import", "from", "if", "else", "elif", "for", "while", "return", "try", "except", "with", "as", "lambda", "yield", "async", "await"]
        case .javascript:
            return ["function", "const", "let", "var", "class", "import", "export", "if", "else", "for", "while", "return", "async", "await", "=>", "this", "new"]
        }
    }
    
    var stringDelimiters: [String] {
        switch self {
        case .swift, .javascript:
            return ["\"", "'", "`"]
        case .python:
            return ["\"", "'", "\"\"\"", "'''"]
        }
    }
}

// MARK: - Code Preview

struct CodePreview: View {
    let text: String
    let language: CodeLanguage
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Language badge
                HStack {
                    Text(language.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                
                // Syntax highlighted code
                SyntaxHighlightedText(text: text, language: language)
                    .padding(8)
            }
        }
        .frame(maxHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Syntax Highlighted Text

struct SyntaxHighlightedText: View {
    let text: String
    let language: CodeLanguage
    
    var body: some View {
        let attributedString = highlightSyntax(text, language: language)
        
        Text(AttributedString(attributedString))
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func highlightSyntax(_ text: String, language: CodeLanguage) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        
        // Default color
        attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        
        // Highlight keywords
        for keyword in language.keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                    guard let match = match else { return }
                    attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                    attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), range: match.range)
                }
            }
        }
        
        // Highlight strings
        for delimiter in language.stringDelimiters {
            let pattern = "\(delimiter)([^\(delimiter)]*?)\(delimiter)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                    guard let match = match else { return }
                    attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
                }
            }
        }
        
        // Highlight numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: []) {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
            }
        }
        
        // Highlight comments
        let commentPattern = language == .swift || language == .javascript ? "//.*" : "#.*"
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: []) {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range)
            }
        }
        
        return attributedString
    }
}

// MARK: - Table Preview

struct TablePreview: View {
    let data: [[String]]
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            Text(cell.isEmpty ? " " : cell)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(6)
                                .frame(minWidth: 80, alignment: .leading)
                                .background(rowIndex == 0 ? Color.accentColor.opacity(0.1) : Color.clear)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Image Preview

struct ImagePreview: View {
    let item: ClipboardItem
    
    var body: some View {
        Group {
            if let imagePath = item.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(6)
            } else {
                Text("Image")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Rich Text Preview

struct RichTextPreview: View {
    let item: ClipboardItem
    
    var body: some View {
        ScrollView {
            Text(item.textForPasting)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Plain Text Preview

struct PlainTextPreview: View {
    let text: String
    
    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - PDF Preview (placeholder - would need PDFKit)

struct PDFPreview: View {
    let item: ClipboardItem
    
    var body: some View {
        // TODO: Implement PDF preview using PDFKit
        Text("PDF Preview (Coming Soon)")
            .foregroundColor(.secondary)
            .frame(maxHeight: 300)
    }
}
