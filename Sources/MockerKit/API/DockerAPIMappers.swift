import Foundation

// Docker list endpoints use SHAPES that differ from the inspect endpoints — wrong types break
// `docker ps`/`docker images` and SDK (Jackson) deserialization. These mirror Docker's
// `ContainerSummary` / `ImageSummary`. Kept as `[String: Any]` (serialized via DockerAPIServer's
// slash-unescaping JSON path), not the inspect DTOs.

/// Docker `ContainerSummary` (one element of `GET /containers/json`).
/// Note vs inspect: `Command` is a STRING (not array), `Created` is a unix INT (not RFC3339),
/// `State` is a lowercase string, `Ports[].PublicPort` is an INT (not a string).
public func mapToContainerListItem(_ c: ContainerInfo) -> [String: Any] {
    let state = c.state == .stopped ? "exited" : c.state.rawValue
    let ports: [[String: Any]] = c.ports.map { p in
        [
            "IP": "0.0.0.0",
            "PrivatePort": Int(p.containerPort),
            "PublicPort": Int(p.hostPort),
            "Type": p.portProtocol.rawValue,
        ]
    }
    return [
        "Id": c.id,
        "Names": ["/\(c.name)"],
        "Image": c.image,
        "ImageID": c.image,
        "Command": c.command,
        "Created": Int(c.created.timeIntervalSince1970),
        "State": state,
        "Status": c.status,
        "Ports": ports,
        "Labels": c.labels,
        "NetworkSettings": ["Networks": [String: Any]()],
        "Mounts": [Any](),
        "HostConfig": ["NetworkMode": "default"],
    ]
}

/// Docker `ImageSummary` (one element of `GET /images/json`).
/// `ImageInfo` (id/repository/tag/size/created/labels) is NOT this shape — map explicitly.
public func mapToImageListItem(_ i: ImageInfo) -> [String: Any] {
    let repo = i.repository.isEmpty ? "<none>" : i.repository
    let tag = i.tag.isEmpty ? "<none>" : i.tag
    let id = i.id.hasPrefix("sha256:") ? i.id : "sha256:\(i.id)"
    return [
        "Id": id,
        "ParentId": "",
        "RepoTags": ["\(repo):\(tag)"],
        "RepoDigests": [Any](),
        "Created": Int(i.created.timeIntervalSince1970),
        "Size": Int(i.size),
        "VirtualSize": Int(i.size),
        "SharedSize": -1,
        "Containers": -1,
        "Labels": i.labels,
    ]
}
