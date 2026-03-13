import ArgumentParser
import MockerKit
import Foundation

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search Docker Hub for images"
    )

    @Argument(help: "Search term")
    var term: String

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Option(name: .long, help: "Max number of search results")
    var limit: Int = 25

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    func run() async throws {
        let urlString = "https://hub.docker.com/v2/search/repositories/?query=\(term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term)&page_size=\(limit)"
        guard let url = URL(string: urlString) else {
            throw MockerError.operationFailed("invalid search URL")
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw MockerError.operationFailed("failed to parse search results")
        }

        let headers = ["NAME", "DESCRIPTION", "STARS", "OFFICIAL"]
        var rows: [[String]] = []
        for result in results.prefix(limit) {
            let name = result["repo_name"] as? String ?? ""
            let description = result["short_description"] as? String ?? ""
            let stars = result["star_count"] as? Int ?? 0
            let official = (result["is_official"] as? Bool ?? false) ? "[OK]" : ""
            let desc = noTrunc ? description : String(description.prefix(45))
            rows.append([name, desc, "\(stars)", official])
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}
