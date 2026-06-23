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
            shmSize: nil, pidsLimit: nil
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
}
