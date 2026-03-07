import SwiftUI
import MockerKit

struct ImageListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var pullReference = ""

    var body: some View {
        VStack(spacing: 8) {
            // Pull bar
            HStack(spacing: 6) {
                TextField("Image to pull (e.g., nginx:latest)", text: $pullReference)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button("Pull") {
                    guard !pullReference.isEmpty else { return }
                    Task {
                        await viewModel.pullImage(pullReference)
                        pullReference = ""
                    }
                }
                .disabled(pullReference.isEmpty)
                .font(.caption)
            }
            .padding(.horizontal, 8)

            if viewModel.images.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No images")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.images) { image in
                    ImageRowView(image: image)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ImageRowView: View {
    let image: ImageInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(image.reference)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(image.shortID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(image.sizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        .padding(.horizontal, 8)
    }
}
