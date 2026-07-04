import Testing
@testable import MockerKit

@Suite("ComposeOrchestrator Tests")
struct ComposeOrchestratorTests {

    @Test("Service order respects depends_on chain")
    func testServiceOrderChain() throws {
        let yaml = """
        version: "3.8"
        services:
          web:
            image: nginx
            depends_on:
              - api
          api:
            image: node
            depends_on:
              - db
          db:
            image: postgres
        """
        let compose = try ComposeFile.parse(yaml)
        let order = compose.serviceOrder()

        // db must come before api, api before web
        let dbIdx = order.firstIndex(of: "db")!
        let apiIdx = order.firstIndex(of: "api")!
        let webIdx = order.firstIndex(of: "web")!

        #expect(dbIdx < apiIdx)
        #expect(apiIdx < webIdx)
    }

    @Test("Service order handles independent services")
    func testServiceOrderIndependent() throws {
        let yaml = """
        version: "3.8"
        services:
          redis:
            image: redis
          postgres:
            image: postgres
          nginx:
            image: nginx
        """
        let compose = try ComposeFile.parse(yaml)
        let order = compose.serviceOrder()
        #expect(order.count == 3)
        #expect(Set(order) == Set(["redis", "postgres", "nginx"]))
    }

    @Test("Compose file filtering preserves requested services")
    func testFilteringServices() throws {
        let yaml = """
        version: "3.8"
        services:
          web:
            image: nginx
          api:
            image: node
          db:
            image: postgres
        """
        let compose = try ComposeFile.parse(yaml)
        let filtered = compose.filtering(services: ["web", "db"])
        #expect(filtered.services.count == 2)
        #expect(filtered.services["web"] != nil)
        #expect(filtered.services["db"] != nil)
        #expect(filtered.services["api"] == nil)
    }

    // MARK: - Image source resolution (issue #14)

    @Test("image only resolves to pull")
    func resolveImageOnly() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
        """).services["app"]!
        #expect(svc.resolveImageSource(projectName: "proj") == .pull(image: "nginx:latest"))
    }

    @Test("build only resolves to build with synthesized tag")
    func resolveBuildOnly() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            build:
              context: .
              target: base
        """).services["app"]!
        let source = svc.resolveImageSource(projectName: "proj")
        guard case .build(let tag, let build) = source else {
            Issue.record("expected .build, got \(source)")
            return
        }
        #expect(tag == "proj-app:latest")
        #expect(build.target == "base")
    }

    @Test("image + build resolves to build, tagged with image name (issue #14)")
    func resolveImageAndBuild() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            image: repro-app
            build:
              context: .
              target: base
        """).services["app"]!
        let source = svc.resolveImageSource(projectName: "proj")
        guard case .build(let tag, _) = source else {
            Issue.record("expected .build (not pull) when image + build are both set; got \(source)")
            return
        }
        // image: is used as the tag, NOT pulled from a registry.
        #expect(tag == "repro-app")
    }

    @Test("image + build with --no-build falls back to pull")
    func resolveImageAndBuildNoBuild() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            image: repro-app
            build:
              context: .
        """).services["app"]!
        #expect(svc.resolveImageSource(projectName: "proj", noBuild: true) == .pull(image: "repro-app"))
    }

    @Test("empty service resolves to none")
    func resolveNone() throws {
        let svc = ComposeService(
            name: "app", image: nil, build: nil, command: [], environment: [:],
            ports: [], volumes: [], networks: [], dependsOn: [], restart: nil,
            labels: [:], hostname: nil, workingDir: nil,
            memLimit: nil, cpus: nil, memReservation: nil, cpusReservation: nil,
            memSwapLimit: nil,
            shmSize: nil, pidsLimit: nil,
            restartPolicyDelay: nil, restartPolicyMaxAttempts: nil, restartPolicyWindow: nil
        )
        #expect(svc.resolveImageSource(projectName: "proj") == .none)
    }

    @Test("imageMatches compares repository suffix and tag")
    func imageMatching() {
        let img = ImageInfo(id: "abc", repository: "proj-app", tag: "latest")
        #expect(ComposeService.imageMatches(img, tag: "proj-app:latest"))
        #expect(ComposeService.imageMatches(img, tag: "proj-app"))  // implicit :latest
        #expect(!ComposeService.imageMatches(img, tag: "proj-app:v2"))
        #expect(!ComposeService.imageMatches(img, tag: "other-app:latest"))
    }

    // MARK: - Volume mount resolution (issue #49)

    @Test("Absolute bind mount included as-is")
    func resolveAbsoluteBindMount() throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts(["/host/data:/container/data"])
        #expect(mounts.count == 1)
        #expect(mounts[0].source == "/host/data")
        #expect(mounts[0].destination == "/container/data")
    }

    @Test(
        "Relative-style sources resolved to absolute path",
        arguments: [
            ("./foo:/bar", "/foo", "/bar"),
            ("../data:/container/data", "/data", "/container/data"),
            ("mydir/data:/container/data", "mydir/data", "/container/data"),
        ]
    )
    func resolveRelativeStyleMounts(spec: String, suffix: String, destination: String) throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts([spec])
        #expect(mounts.count == 1)
        #expect(mounts[0].source.hasPrefix("/"))
        #expect(mounts[0].source.hasSuffix(suffix))
        #expect(mounts[0].destination == destination)
    }

    @Test("Named volume skipped")
    func skipNamedVolume() throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts(["mydata:/container/data"])
        #expect(mounts.isEmpty)
    }

    @Test("Anonymous volume included")
    func includeAnonymousVolume() throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts(["/container/data"])
        #expect(mounts.count == 1)
        #expect(mounts[0].source == "")
        #expect(mounts[0].destination == "/container/data")
    }

    @Test("Mix of bind mounts, named volumes, and anonymous volumes")
    func resolveMixedVolumes() throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts([
            "/abs/path:/app/data",
            "./relative:/app/rel",
            "namedvol:/app/named",
            "/app/anon",
            "sub/dir:/app/sub",
        ])
        #expect(mounts.count == 4)  // namedvol skipped
        let sources = mounts.map(\.source)
        #expect(sources.contains("/abs/path"))
        #expect(sources.contains(""))  // anonymous
        #expect(sources.contains(where: { $0.hasSuffix("/relative") }))
        #expect(sources.contains(where: { $0.hasSuffix("sub/dir") }))
    }

    @Test("Read-only relative bind mount preserves ro flag")
    func resolveRelativeReadOnly() throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts(["./data:/container/data:ro"])
        #expect(mounts.count == 1)
        #expect(mounts[0].readOnly == true)
        #expect(mounts[0].destination == "/container/data")
        #expect(mounts[0].source.hasSuffix("/data"))
    }

    @Test("Home-relative path resolved")
    func resolveHomeRelativePath() throws {
        let mounts = try ComposeOrchestrator.resolveVolumeMounts(["~/data:/container/data"])
        #expect(mounts.count == 1)
        #expect(mounts[0].source.hasPrefix("/"))
        #expect(mounts[0].source.contains("data"))
        #expect(mounts[0].destination == "/container/data")
    }

    // MARK: - reconcileDecision (issue #59)

    private func singleServiceFile() throws -> ComposeFile {
        try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
        """)
    }

    private func observed(name: String, serviceName: String, configHash: String?) -> ObservedContainer {
        ObservedContainer(name: name, serviceName: serviceName, configHash: configHash)
    }

    @Test("reconcileDecision: observed container matches hash + defaults → .keep")
    func reconcileObservedMatchesDefaults() throws {
        let file = try singleServiceFile()
        let svc = file.services["app"]!
        let hash = ComposeService.hash(of: svc)
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [
                observed(name: "proj-app-1", serviceName: "app", configHash: hash)
            ],
            composeFile: file,
            projectName: "proj",
            forceRecreate: false,
            noRecreate: false
        )
        #expect(actions == [ReconcileAction(serviceName: "app", kind: .keep)])
    }

    @Test("reconcileDecision: observed container matches hash + --force-recreate → .removeAndRecreate")
    func reconcileForceRecreateOverridesKeep() throws {
        let file = try singleServiceFile()
        let svc = file.services["app"]!
        let hash = ComposeService.hash(of: svc)
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [
                observed(name: "proj-app-1", serviceName: "app", configHash: hash)
            ],
            composeFile: file,
            projectName: "proj",
            forceRecreate: true,
            noRecreate: false
        )
        #expect(actions == [ReconcileAction(serviceName: "app", kind: .removeAndRecreate)])
    }

    @Test("reconcileDecision: observed container matches hash + --no-recreate → .keep")
    func reconcileNoRecreateEvenWithDrift() throws {
        let file = try singleServiceFile()
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [
                observed(name: "proj-app-1", serviceName: "app", configHash: "stale-different-value")
            ],
            composeFile: file,
            projectName: "proj",
            forceRecreate: false,
            noRecreate: true
        )
        #expect(actions == [ReconcileAction(serviceName: "app", kind: .keep)])
    }

    @Test("reconcileDecision: observed container has diverged hash + defaults → .removeAndRecreate")
    func reconcileHashDriftDefaults() throws {
        let file = try singleServiceFile()
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [
                observed(name: "proj-app-1", serviceName: "app", configHash: "sha256:different")
            ],
            composeFile: file,
            projectName: "proj",
            forceRecreate: false,
            noRecreate: false
        )
        #expect(actions == [ReconcileAction(serviceName: "app", kind: .removeAndRecreate)])
    }

    @Test("reconcileDecision: multiple services + --force-recreate → all .removeAndRecreate")
    func reconcileMultipleServicesForceRecreate() throws {
        let file = try ComposeFile.parse("""
        services:
          web:
            image: nginx:alpine
          db:
            image: redis:7
        """)
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [
                observed(name: "proj-web-1", serviceName: "web", configHash: ComposeService.hash(of: file.services["web"]!)),
                observed(name: "proj-db-1", serviceName: "db", configHash: ComposeService.hash(of: file.services["db"]!)),
            ],
            composeFile: file,
            projectName: "proj",
            forceRecreate: true,
            noRecreate: false
        )
        #expect(actions == [
            ReconcileAction(serviceName: "db", kind: .removeAndRecreate),
            ReconcileAction(serviceName: "web", kind: .removeAndRecreate),
        ])
    }

    @Test("reconcileDecision: empty observedContainers (post-prefix-filter) → all .noOp")
    func reconcileIgnoresForeignProject() throws {
        let file = try singleServiceFile()
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [],
            composeFile: file,
            projectName: "proj",
            forceRecreate: false,
            noRecreate: false
        )
        #expect(actions == [ReconcileAction(serviceName: "app", kind: .noOp)])
    }

    @Test("reconcileDecision: empty composeFile → empty actions list")
    func reconcileEmptyFile() {
        let empty = ComposeFile()
        let actions = ComposeOrchestrator.reconcileDecision(
            observedContainers: [
                observed(name: "proj-app-1", serviceName: "app", configHash: "sha256:x")
            ],
            composeFile: empty,
            projectName: "proj",
            forceRecreate: false,
            noRecreate: false
        )
        #expect(actions.isEmpty)
    }
}
