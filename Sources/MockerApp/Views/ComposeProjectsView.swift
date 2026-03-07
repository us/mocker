import SwiftUI
import MockerKit

struct ComposeProjectsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    /// Group containers by compose project label.
    private var projects: [String: [ContainerInfo]] {
        var result: [String: [ContainerInfo]] = [:]
        for container in viewModel.containers {
            if let project = container.labels["com.mocker.compose.project"] {
                result[project, default: []].append(container)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 4) {
            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No compose projects")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Use 'mocker compose up' to start a project")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(Array(projects.keys.sorted()), id: \.self) { project in
                    ComposeProjectRow(name: project, containers: projects[project] ?? [])
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct ComposeProjectRow: View {
    let name: String
    let containers: [ContainerInfo]

    private var runningCount: Int {
        containers.filter { $0.state == .running }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.purple)
                Text(name)
                    .font(.headline)
                Spacer()
                Text("\(runningCount)/\(containers.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(containers) { container in
                HStack(spacing: 6) {
                    Circle()
                        .fill(container.state == .running ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(container.labels["com.mocker.compose.service"] ?? container.name)
                        .font(.caption)
                    Spacer()
                    Text(container.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }
}
