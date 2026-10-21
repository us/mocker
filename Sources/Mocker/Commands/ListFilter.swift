import MockerKit

/// A `--filter key=value` whose key the command knows how to evaluate.
///
/// Docker rejects a key it does not know (`invalid filter 'foo'`). Ignoring it instead
/// returned the unfiltered list, which turned `images -f dangling=true` into "every
/// image" and the usual cleanup `rmi $(images -qf dangling=true)` into "delete everything".
struct ListFilter {
    let key: String
    let value: String

    static func parse(_ raw: [String], supported: Set<String>) throws -> [ListFilter] {
        try raw.map { filter in
            let parts = filter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw MockerError.operationFailed("bad format of filter (expected name=value): \(filter)")
            }
            guard supported.contains(String(parts[0])) else {
                throw MockerError.operationFailed("invalid filter '\(parts[0])'")
            }
            return ListFilter(key: String(parts[0]), value: String(parts[1]))
        }
    }
}
