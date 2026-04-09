import SwiftUI

struct RefPickerView: View {
    let title: String
    let refs: [GitRef]
    @Binding var selection: GitRef?
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var highlightedIndex: Int?

    private var filteredRefs: [GitRef] {
        if searchText.isEmpty { return refs }
        return refs.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button {
            isPresented.toggle()
            searchText = ""
            highlightedIndex = nil
        } label: {
            HStack {
                Text(selection?.displayName ?? title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            let filtered = filteredRefs

            VStack(spacing: 0) {
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                    .onKeyPress(.upArrow) {
                        moveHighlight(by: -1, count: filtered.count)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveHighlight(by: 1, count: filtered.count)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if let index = highlightedIndex, index < filtered.count {
                            selection = filtered[index]
                            isPresented = false
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        isPresented = false
                        return .handled
                    }
                    .onChange(of: searchText) {
                        highlightedIndex = filtered.isEmpty ? nil : 0
                    }

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, ref in
                                Button {
                                    selection = ref
                                    isPresented = false
                                } label: {
                                    HStack {
                                        Text(ref.displayName)
                                            .lineLimit(1)
                                        if let subject = ref.commitSubject {
                                            Text(subject)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(index == highlightedIndex ? Color.accentColor.opacity(0.2) : .clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(ref.id)
                            }
                        }
                    }
                    .onChange(of: highlightedIndex) {
                        if let index = highlightedIndex, index < filtered.count {
                            proxy.scrollTo(filtered[index].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 350, height: 400)
        }
    }

    private func moveHighlight(by delta: Int, count: Int) {
        guard count > 0 else { return }
        if let current = highlightedIndex {
            highlightedIndex = max(0, min(count - 1, current + delta))
        } else {
            highlightedIndex = delta > 0 ? 0 : count - 1
        }
    }
}
