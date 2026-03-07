import SwiftUI
import MockerKit

struct ContainerListView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 4) {
            if viewModel.containers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No containers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.containers) { container in
                    ContainerRowView(container: container)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct ContainerRowView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let container: ContainerInfo

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(container.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(container.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            if container.state == .running {
                Button(action: { Task { await viewModel.stopContainer(container.id) } }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Stop")
            }

            Button(action: { Task { await viewModel.removeContainer(container.id) } }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }

    private var statusColor: Color {
        switch container.state {
        case .running: .green
        case .paused: .yellow
        case .exited, .stopped: .red
        default: .gray
        }
    }
}
