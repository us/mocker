import ArgumentParser
import MockerKit

struct ImageListOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Only show image IDs")
    var quiet = false

    @Flag(name: .shortAndLong, help: "Show all images (default hides intermediate images)")
    var all = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .long, help: "Show digests")
    var digests = false

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    @Flag(name: .long, help: "List images in tree format (experimental)")
    var tree = false

    func render() async throws {
        // --all/--digests/--tree are accepted for Docker compatibility but are no-ops;
        // ImageInfo has no intermediate-image, digest, or parent-tree data. Wire them
        // up when ImageManager surfaces that data.
        let config = MockerConfig()
        let manager = try ImageManager(config: config)
        let images = filtered(try await manager.list())

        if quiet {
            for image in images {
                print(noTrunc ? image.id : image.shortID)
            }
            return
        }

        if format != nil {
            for img in images {
                print(formatLine(img))
            }
            return
        }

        let headers = ["Repository", "Tag", "Image ID", "Created", "Size"]
        let rows = images.map { img in
            [
                img.repository,
                img.tag,
                noTrunc ? img.id : img.shortID,
                img.createdAgo,
                img.sizeString,
            ]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }

    /// Render a single image through the `--format` template. Pure; safe to unit-test.
    func formatLine(_ img: ImageInfo) -> String {
        var output = format ?? ""
        output = output.replacingOccurrences(of: "{{.ID}}", with: noTrunc ? img.id : img.shortID)
        output = output.replacingOccurrences(of: "{{.Repository}}", with: img.repository)
        output = output.replacingOccurrences(of: "{{.Tag}}", with: img.tag)
        output = output.replacingOccurrences(of: "{{.Digest}}", with: "<none>")
        output = output.replacingOccurrences(of: "{{.CreatedAt}}", with: img.createdAgo)
        output = output.replacingOccurrences(of: "{{.Size}}", with: img.sizeString)
        output = output.replacingOccurrences(of: "{{.Labels}}", with: img.labels.map { "\($0.key)=\($0.value)" }.joined(separator: ","))
        return output
    }

    /// Apply Docker-style `--filter` predicates. Pure; safe to unit-test.
    func filtered(_ images: [ImageInfo]) -> [ImageInfo] {
        var images = images
        for f in filter {
            let parts = f.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            switch key {
            case "reference":
                // Docker matches a bare repo (any tag) or an exact repo:tag. Glob (`*`) is not supported.
                images = images.filter { $0.repository == value || $0.reference == value }
            case "label":
                let labelParts = value.split(separator: "=", maxSplits: 1)
                if labelParts.count == 2 {
                    images = images.filter { $0.labels[String(labelParts[0])] == String(labelParts[1]) }
                } else {
                    images = images.filter { $0.labels[value] != nil }
                }
            default:
                break
            }
        }
        return images
    }
}
