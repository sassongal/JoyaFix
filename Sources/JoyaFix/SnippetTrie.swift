import Foundation

/// A Trie (prefix tree) optimized for suffix matching of snippet triggers
/// PERFORMANCE: O(k) lookup where k = trigger length, vs O(n log n) for sorting approach
class SnippetTrie {
    private class TrieNode {
        var children: [Character: TrieNode] = [:]
        var snippet: Snippet?
        var isEndOfTrigger: Bool = false
    }

    private var root = TrieNode()

    /// Inserts a snippet into the trie (stored in reverse for suffix matching)
    func insert(snippet: Snippet) {
        var node = root
        // Store trigger in reverse for efficient suffix matching
        for char in snippet.trigger.reversed() {
            if node.children[char] == nil {
                node.children[char] = TrieNode()
            }
            node = node.children[char]!
        }
        node.isEndOfTrigger = true
        node.snippet = snippet
    }

    /// Finds a matching snippet by checking if buffer ends with any trigger
    /// Returns the longest matching trigger to handle cases like "!m" and "!mail"
    func findMatch(in buffer: String, requireWordBoundary: Bool = true) -> Snippet? {
        var bestMatch: Snippet?
        var node = root

        // Walk backwards through the buffer
        for (index, char) in buffer.reversed().enumerated() {
            guard let nextNode = node.children[char] else {
                // No more matches possible
                break
            }
            node = nextNode

            // If we found a complete trigger, check word boundary
            if node.isEndOfTrigger, let snippet = node.snippet {
                if !requireWordBoundary {
                    bestMatch = snippet
                } else {
                    // Check word boundary: position in original buffer
                    let triggerStartIndex = buffer.count - index - 1
                    if isWordBoundary(at: triggerStartIndex, in: buffer) {
                        bestMatch = snippet
                    }
                }
            }
        }

        return bestMatch
    }

    /// Checks if the position is at a word boundary (start of buffer or after whitespace/punctuation)
    private func isWordBoundary(at position: Int, in text: String) -> Bool {
        // If at the start of the text, it's a word boundary
        if position == 0 {
            return true
        }

        // Check the character before the trigger
        let index = text.index(text.startIndex, offsetBy: position - 1)
        let charBefore = text[index]

        // Word boundary is whitespace, punctuation, or newline
        return charBefore.isWhitespace || charBefore.isPunctuation || charBefore.isNewline
    }

    /// Rebuilds the entire trie from a list of snippets
    /// Call this when snippets are added, removed, or modified
    func rebuild(from snippets: [Snippet]) {
        root = TrieNode()
        for snippet in snippets {
            insert(snippet: snippet)
        }
    }

    /// Returns the number of snippets in the trie
    func count() -> Int {
        return countNodes(node: root)
    }

    private func countNodes(node: TrieNode) -> Int {
        var count = node.isEndOfTrigger ? 1 : 0
        for child in node.children.values {
            count += countNodes(node: child)
        }
        return count
    }
}
