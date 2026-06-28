import Foundation
import Testing

@testable import MockerKit

@Suite("Docker API server — unit")
struct DockerAPIServerTests {

    // MARK: - Path normalization (version leniency + query strip)

    @Test("strips a leading /vX.YY version prefix (any version, no min/max enforcement)")
    func stripsVersionPrefix() {
        #expect(HTTPHandler.normalizePath("/v1.47/version") == "/version")
        #expect(HTTPHandler.normalizePath("/v1.32/containers/json") == "/containers/json")  // testcontainers pins low
        #expect(HTTPHandler.normalizePath("/v9.99/info") == "/info")  // never reject a too-new path
    }

    @Test("strips the query string")
    func stripsQuery() {
        #expect(HTTPHandler.normalizePath("/containers/json?all=1&filters=x") == "/containers/json")
        #expect(HTTPHandler.normalizePath("/v1.43/version?foo=bar") == "/version")
    }

    @Test("unversioned paths pass through unchanged")
    func unversionedUnchanged() {
        #expect(HTTPHandler.normalizePath("/_ping") == "/_ping")
        #expect(HTTPHandler.normalizePath("/version") == "/version")
    }

    @Test("does not mistake non-version /v… paths for a version prefix")
    func doesNotEatVolumes() {
        #expect(HTTPHandler.normalizePath("/volumes") == "/volumes")
        #expect(HTTPHandler.normalizePath("/volumes/create") == "/volumes/create")  // "v"+non-numeric
        #expect(HTTPHandler.normalizePath("/version") == "/version")  // "ersion" has no slash → kept
    }

    // MARK: - Socket safety (lstat preflight)

    @Test("prepareSocketPath refuses to unlink a non-socket file (no clobbering regular files/symlinks)")
    func refusesNonSocket() throws {
        let path = NSTemporaryDirectory() + "mocker-test-regular-\(getpid()).file"
        FileManager.default.createFile(atPath: path, contents: Data("not a socket".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: (any Error).self) {
            try DockerAPIServer.prepareSocketPath(path)
        }
        // the regular file must still be there (we refused to remove it)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("prepareSocketPath creates a 0700 parent dir and tolerates a missing socket")
    func createsParentDir() throws {
        let dir = NSTemporaryDirectory() + "mocker-test-sock-dir-\(getpid())"
        let path = dir + "/docker.sock"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try DockerAPIServer.prepareSocketPath(path)  // must not throw when nothing is there
        #expect(FileManager.default.fileExists(atPath: dir))
        let perms = (try FileManager.default.attributesOfItem(atPath: dir)[.posixPermissions]) as? NSNumber
        #expect(perms?.int16Value == 0o700)
    }

    // MARK: - Docker list-item mappers (shapes differ from inspect — wrong types break docker ps)

    @Test("mapToContainerListItem emits the Docker ContainerSummary shape & types")
    func containerListItem() {
        let c = ContainerInfo(
            id: "abc", name: "web", image: "nginx:latest", state: .running, status: "Up 2m",
            created: Date(timeIntervalSince1970: 1_700_000_000),
            ports: [PortMapping(hostPort: 8080, containerPort: 80, portProtocol: .tcp)],
            labels: ["a": "b"], command: "nginx -g daemon", pid: 1, networkAddress: "10.0.0.1")
        let m = mapToContainerListItem(c)
        #expect(m["Id"] as? String == "abc")
        #expect(m["Names"] as? [String] == ["/web"])      // leading slash
        #expect(m["Command"] as? String == "nginx -g daemon")  // STRING, not array
        #expect(m["Created"] as? Int == 1_700_000_000)    // unix int, not RFC3339
        #expect(m["State"] as? String == "running")       // lowercase string
        let port = (m["Ports"] as? [[String: Any]])?.first
        #expect(port?["PrivatePort"] as? Int == 80)       // INT, not string
        #expect(port?["PublicPort"] as? Int == 8080)
        #expect(port?["Type"] as? String == "tcp")
    }

    @Test("stopped container maps State to Docker 'exited'")
    func containerListExited() {
        let c = ContainerInfo(id: "x", name: "w", image: "i", state: .stopped, status: "Exited",
                              created: Date(), ports: [], labels: [:], command: "", pid: nil, networkAddress: "")
        #expect(mapToContainerListItem(c)["State"] as? String == "exited")
    }

    @Test("mapToImageListItem emits the Docker ImageSummary shape")
    func imageListItem() {
        let i = ImageInfo(id: "deadbeef", repository: "nginx", tag: "latest", size: 1234,
                          created: Date(timeIntervalSince1970: 1_700_000_000), labels: [:])
        let m = mapToImageListItem(i)
        #expect(m["Id"] as? String == "sha256:deadbeef")  // sha256-prefixed
        #expect(m["RepoTags"] as? [String] == ["nginx:latest"])
        #expect(m["Created"] as? Int == 1_700_000_000)
        #expect(m["Size"] as? Int == 1234)
        #expect(m["SharedSize"] as? Int == -1)
    }

    @Test("image with existing sha256 id is not double-prefixed; empty repo → <none>")
    func imageListEdge() {
        let i = ImageInfo(id: "sha256:abc", repository: "", tag: "", size: 0, created: Date(), labels: [:])
        let m = mapToImageListItem(i)
        #expect(m["Id"] as? String == "sha256:abc")
        #expect(m["RepoTags"] as? [String] == ["<none>:<none>"])
    }

    // MARK: - The runCLI drain fix: large output must not deadlock

    /// `runCLI` is private + bound to the container binary, so this reproduces its EXACT pattern
    /// (Process + two pipes + terminationHandler + concurrent detached drain) against a command
    /// that emits ~1.3 MB — far past the ~64 KB pipe buffer. With the OLD code (read inside
    /// terminationHandler) the child blocks on write before exit and this hangs forever; with the
    /// concurrent drain it completes and returns the full output.
    @Test("concurrent drain reads >64KB output without deadlocking", .timeLimit(.minutes(1)))
    func largeOutputNoDeadlock() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/seq")
        process.arguments = ["1", "200000"]  // ~1.3 MB of output
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        let outHandle = pipe.fileHandleForReading
        let outTask = Task.detached { outHandle.readDataToEndOfFile() }
        let status: Int32 = await withCheckedContinuation { c in
            process.terminationHandler = { p in c.resume(returning: p.terminationStatus) }
        }
        let out = String(data: await outTask.value, encoding: .utf8) ?? ""

        #expect(status == 0)
        let lines = out.split(separator: "\n")
        #expect(lines.count == 200_000)
        #expect(lines.first == "1")
        #expect(lines.last == "200000")
    }
}
