import SwiftUI

struct AdvancedFiltersPanel: View {
    @Binding var searchOptions: AdvancedSearchOptions
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showCustomDatePicker = false
    
    var body: some View {
        VStack(spacing: 12) {
            Divider()
            
            // Date Range Filter
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Date Range")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Picker("", selection: $searchOptions.dateRange) {
                    ForEach(DateRangeFilter.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 10))
                
                if searchOptions.dateRange == .custom {
                    HStack {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .font(.system(size: 10))
                        Text("to")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .font(.system(size: 10))
                    }
                    .onChange(of: customStartDate) { _, newValue in
                        searchOptions.customDateRange = CustomDateRange(start: newValue, end: customEndDate)
                    }
                    .onChange(of: customEndDate) { _, newValue in
                        searchOptions.customDateRange = CustomDateRange(start: customStartDate, end: newValue)
                    }
                    .onAppear {
                        if searchOptions.customDateRange == nil {
                            // Initialize with default range (last 30 days)
                            let end = Date()
                            let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
                            customStartDate = start
                            customEndDate = end
                            searchOptions.customDateRange = CustomDateRange(start: start, end: end)
                        } else {
                            customStartDate = searchOptions.customDateRange!.startDate
                            customEndDate = searchOptions.customDateRange!.endDate
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content Type Filter
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Content Type")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                FlowLayout(spacing: 6) {
                    ForEach(ContentTypeFilter.allCases) { contentType in
                        ContentTypeToggle(
                            contentType: contentType,
                            isSelected: searchOptions.contentTypes.contains(contentType),
                            onToggle: {
                                if searchOptions.contentTypes.contains(contentType) {
                                    searchOptions.contentTypes.remove(contentType)
                                } else {
                                    searchOptions.contentTypes.insert(contentType)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Clear Filters Button
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        searchOptions = AdvancedSearchOptions()
                        customStartDate = Date()
                        customEndDate = Date()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Clear Filters")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Content Type Toggle

struct ContentTypeToggle: View {
    let contentType: ContentTypeFilter
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: contentType.icon)
                    .font(.system(size: 10))
                Text(contentType.rawValue)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (for wrapping content type buttons)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}
