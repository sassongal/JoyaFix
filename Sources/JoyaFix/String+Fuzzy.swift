import Foundation

extension String {
    /// Calculates fuzzy match score using Levenshtein distance
    /// Returns a score between 0.0 (no match) and 1.0 (exact match)
    /// - Parameter word: The search term to match against
    /// - Returns: A score between 0.0 and 1.0, where higher is better
    func fuzzyScore(word: String) -> Double {
        guard !word.isEmpty else { return 1.0 } // Empty search matches everything
        guard !self.isEmpty else { return 0.0 } // Empty string matches nothing
        
        let selfLower = self.lowercased()
        let wordLower = word.lowercased()
        
        // Exact match (case-insensitive)
        if selfLower == wordLower {
            return 1.0
        }
        
        // Substring match (case-insensitive) - high score
        if selfLower.contains(wordLower) {
            return 0.8
        }
        
        // Calculate Levenshtein distance
        let distance = levenshteinDistance(selfLower, wordLower)
        let maxLength = max(selfLower.count, wordLower.count)
        
        guard maxLength > 0 else { return 0.0 }
        
        // Convert distance to score (0.0 = worst, 1.0 = best)
        // Score decreases as distance increases
        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        
        // Normalize to 0.0-1.0 range and apply threshold
        return max(0.0, similarity)
    }
    
    /// Calculates Levenshtein distance between two strings
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: The minimum number of single-character edits needed to transform s1 into s2
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        // Create matrix
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        // Initialize first row and column
        for i in 0...s1Count {
            matrix[i][0] = i
        }
        for j in 0...s2Count {
            matrix[0][j] = j
        }
        
        // Fill matrix
        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i - 1][j] + 1,      // Deletion
                    matrix[i][j - 1] + 1,      // Insertion
                    matrix[i - 1][j - 1] + cost // Substitution
                )
            }
        }
        
        return matrix[s1Count][s2Count]
    }
}

