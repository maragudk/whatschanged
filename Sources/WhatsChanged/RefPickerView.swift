import SwiftUI

struct RefPickerView: View {
    let title: String
    let refs: [GitRef]
    @Binding var selection: GitRef?

    @State private var isPresented = false
    @State private var searchText = ""

    private var filteredRefs: [GitRef] {
        if searchText.isEmpty { return refs }
        return refs.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button {
            isPresented.toggle()
            searchText = ""
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
            VStack(spacing: 0) {
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)

                Divider()

                List(filteredRefs) { ref in
                    Button {
                        selection = ref
                        isPresented = false
                    } label: {
                        HStack {
                            Text(ref.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text(ref.type.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(width: 350, height: 400)
        }
    }
}
