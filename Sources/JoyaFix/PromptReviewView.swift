import SwiftUI

struct PromptReviewView: View {
    @Binding var promptText: String
    @State private var refineText: String = ""
    @State private var isRefining: Bool = false
    @FocusState private var isRefineFieldFocused: Bool
    
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onRefine: (String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                Text("Review Enhanced Prompt")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                
                // Close button
                Button(action: {
                    onCancel()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Close")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            // Prompt Text Editor
            VStack(alignment: .leading, spacing: 8) {
                Text("Enhanced Prompt:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $promptText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            }
            .padding(.horizontal)
            
            // Refine Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Refine (optional):")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("e.g., 'Make it shorter' or 'Add more context'", text: $refineText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isRefining)
                        .focused($isRefineFieldFocused)
                        .onSubmit {
                            if !refineText.isEmpty && !isRefining {
                                isRefining = true
                                onRefine(refineText)
                                refineText = ""
                            }
                        }
                    
                    Button(action: {
                        if !refineText.isEmpty && !isRefining {
                            isRefining = true
                            onRefine(refineText)
                            refineText = ""
                        }
                    }) {
                        if isRefining {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(refineText.isEmpty || isRefining)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel", action: {
                    onCancel()
                })
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Confirm & Paste", action: {
                    onConfirm()
                })
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 700, height: 600)  // Larger for better prompt readability
        .background(Color(NSColor.windowBackgroundColor))
    }
}

