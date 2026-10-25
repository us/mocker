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
        let images = try filtered(try await manager.list())

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
    func filtered(_ images: [ImageInfo]) throws -> [ImageInfo] {
        var images = images
        for f in try ListFilter.parse(filter, supported: ["dangling", "reference", "label"]) {
            switch f.key {
            case "dangling":
                // The same set `image prune` removes, so `rmi $(images -qf dangling=true)`
                // deletes only untagged builds. Any other value must fail rather than match all.
                let dangling: Bool
                switch f.value.lowercased() {
                case "true", "1": dangling = true
                case "false", "0": dangling = false
                default: throw MockerError.operationFailed("invalid filter 'dangling=\(f.value)'")
                }
                images = images.filter { ImageManager.isDangling($0) == dangling }
            case "reference":
                // Docker matches a bare repo (any tag) or an exact repo:tag, by the name
                // it shows: a pulled `alpine` is stored as `docker.io/library/alpine`.
                // Glob (`*`) is not supported.
                images = images.filter { image in
                    [image.repository, Self.familiar(image.repository)].contains {
                        $0 == f.value || "\($0):\(image.tag)" == f.value
                    }
                }
            case "label":
                let labelParts = f.value.split(separator: "=", maxSplits: 1)
                if labelParts.count == 2 {
                    images = images.filter { $0.labels[String(labelParts[0])] == String(labelParts[1]) }
                } else {
                    images = images.filter { $0.labels[f.value] != nil }
                }
            default:
                break  // unreachable: `parse` rejected every other key
            }
        }
        return images
    }

    /// `alpine` for `docker.io/library/alpine`, `acme/app` for `docker.io/acme/app`.
    private static func familiar(_ repository: String) -> String {
        for prefix in ["docker.io/library/", "docker.io/"] where repository.hasPrefix(prefix) {
            return String(repository.dropFirst(prefix.count))
        }
        return repository
    }
}
