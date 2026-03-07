import SwiftUI
import MockerKit

struct MenuBarView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
                Text("Mocker")
                    .font(.headline)
                Spacer()
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tab Picker
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(AppViewModel.Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Content
            ScrollView {
                switch viewModel.selectedTab {
                case .containers:
                    ContainerListView()
                case .images:
                    ImageListView()
                case .compose:
                    ComposeProjectsView()
                }
            }
            .frame(maxHeight: 400)

            Divider()

            // Footer
            HStack {
                if let error = viewModel.errorMessage {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 380)
        .task {
            await viewModel.refresh()
        }
    }
}
