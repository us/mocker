import Foundation

/// Reorders a top-level `mocker compose` argument vector so that Docker-style
/// global flags placed BEFORE the subcommand (e.g. `compose -f a.yaml -f b.yaml pull`)
/// are relocated to AFTER the subcommand token, where swift-argument-parser's
/// per-subcommand `@OptionGroup` can actually parse them.
///
/// Only the compose-level global options `-f`/`--file` and `-p`/`--project-name`
/// are relocated; everything else is left exactly where it is so the parser's
/// normal validation and error messages are preserved. This is a pure function
/// so it can be unit-tested without spawning the CLI.
enum ComposeArgNormalizer {
    /// Flags that take a separate value token and may legitimately appear before
    /// the compose subcommand (Docker places them there).
    private static let valueFlags: Set<String> = ["-f", "--file", "-p", "--project-name"]

    static func reorder(_ args: [String]) -> [String] {
        guard args.first == "compose" else { return args }

        var relocated: [String] = []   // global flags to move after the subcommand
        var leading: [String] = []      // other pre-subcommand tokens (left untouched)
        var index = 1
        var subcommandIndex: Int?

        while index < args.count {
            let token = args[index]

            // The first non-flag token is the subcommand verb.
            if !token.hasPrefix("-") {
                subcommandIndex = index
                break
            }

            // Equals-form (`--file=a.yaml` / `-f=a.yaml`): relocate as a single token.
            if let eq = token.firstIndex(of: "="),
               valueFlags.contains(String(token[token.startIndex..<eq])) {
                relocated.append(token)
                index += 1
                continue
            }

            if valueFlags.contains(token) {
                relocated.append(token)
                // Consume the following value token unless it is itself a flag
                // (missing value — let ArgumentParser report it normally).
                if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                    relocated.append(args[index + 1])
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            // Unknown pre-subcommand flag: leave it in place so the parser errors
            // exactly as it does today (no behaviour change for these).
            leading.append(token)
            index += 1
        }

        // No subcommand verb found (e.g. `compose -f a.yaml` with no verb): leave
        // args untouched so ArgumentParser produces its normal help/usage output.
        guard let subIdx = subcommandIndex else { return args }

        var result: [String] = ["compose"]
        result.append(contentsOf: leading)
        result.append(args[subIdx])
        result.append(contentsOf: relocated)
        if subIdx + 1 < args.count {
            result.append(contentsOf: args[(subIdx + 1)...])
        }
        return result
    }
}
