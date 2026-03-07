import Foundation

/// Errors that can occur during Mocker operations.
public enum MockerError: Error, LocalizedError, Sendable {
    case containerNotFound(String)
    case imageNotFound(String)
    case networkNotFound(String)
    case volumeNotFound(String)
    case containerAlreadyExists(String)
    case containerNotRunning(String)
    case invalidPortMapping(String)
    case invalidVolumeMount(String)
    case invalidImageReference(String)
    case composeFileNotFound(String)
    case composeParseError(String)
    case buildError(String)
    case registryError(String)
    case frameworkUnavailable
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .containerNotFound(let id):
            "Error response from daemon: No such container: \(id)"
        case .imageNotFound(let name):
            "Error response from daemon: No such image: \(name)"
        case .networkNotFound(let name):
            "Error response from daemon: network \(name) not found"
        case .volumeNotFound(let name):
            "Error response from daemon: get \(name): no such volume"
        case .containerAlreadyExists(let name):
            "Error response from daemon: Conflict. The container name \"/\(name)\" is already in use. You have to remove (or rename) that container to be able to reuse that name."
        case .containerNotRunning(let id):
            "Error response from daemon: Container \(id) is not running"
        case .invalidPortMapping(let value):
            "Invalid port mapping: \(value). Expected format: hostPort:containerPort[/protocol]"
        case .invalidVolumeMount(let value):
            "Invalid volume mount: \(value). Expected format: source:destination[:ro]"
        case .invalidImageReference(let value):
            "invalid reference format: \(value)"
        case .composeFileNotFound(let path):
            "no configuration file provided: not found: \(path)"
        case .composeParseError(let detail):
            "Failed to parse compose file: \(detail)"
        case .buildError(let detail):
            "failed to solve: \(detail)"
        case .registryError(let detail):
            "Error response from daemon: \(detail)"
        case .frameworkUnavailable:
            "Apple Containerization framework is not available. macOS 26+ required."
        case .operationFailed(let detail):
            "Error response from daemon: \(detail)"
        }
    }
}
