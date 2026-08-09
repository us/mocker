import Testing
import Foundation
@testable import MockerKit

@Suite("Compose network lifecycle")
struct ComposeNetworkLifecycleTests {
    private func parse(_ yaml: String) throws -> ComposeFile {
        try ComposeFile.parse(yaml)
    }

    @Test("external: true is parsed, and defaults to false")
    func parsesExternal() throws {
        let compose = try parse("""
        networks:
          shared:
            external: true
          owned:
        """)

        #expect(compose.networks["shared"]?.external == true)
        #expect(compose.networks["owned"]?.external == false)
    }

    @Test("Legacy external mapping form is treated as external")
    func parsesLegacyExternalMapping() throws {
        let compose = try parse("""
        networks:
          shared:
            external:
              name: already-there
        """)

        #expect(compose.networks["shared"]?.external == true)
        #expect(compose.networks["shared"]?.runtimeName(projectName: "proj") == "already-there")
    }

    @Test("An explicit name: is used verbatim, without the project prefix")
    func explicitNameWins() throws {
        let compose = try parse("""
        networks:
          backend:
            name: shared-backend
        """)

        #expect(compose.networks["backend"]?.runtimeName(projectName: "proj") == "shared-backend")
    }

    @Test("Project-owned networks are namespaced")
    func ownedNetworkIsNamespaced() throws {
        let compose = try parse("networks:\n  backend:\n")

        #expect(compose.networks["backend"]?.runtimeName(projectName: "proj") == "proj-backend")
    }

    @Test("up creates owned networks and never external ones")
    func networksToCreateSkipsExternal() throws {
        let compose = try parse("""
        networks:
          backend:
          frontend:
            driver: bridge
          shared:
            external: true
          named:
            name: custom-net
        """)

        let created = ComposeOrchestrator.networksToCreate(composeFile: compose, projectName: "proj")

        #expect(created.map(\.name) == ["proj-backend", "proj-frontend", "custom-net"])
        #expect(created.allSatisfy { $0.driver == "bridge" })
    }

    @Test("down removes exactly what up created")
    func networksToRemoveMirrorsCreate() throws {
        let compose = try parse("""
        networks:
          backend:
          shared:
            external: true
        """)

        let created = ComposeOrchestrator.networksToCreate(composeFile: compose, projectName: "proj").map(\.name)
        let removed = ComposeOrchestrator.networksToRemove(composeFile: compose, projectName: "proj")

        #expect(created == removed)
        #expect(!removed.contains("shared"))
    }

    @Test("A project that declares no networks still gets its own default network")
    func implicitDefaultNetwork() throws {
        let compose = try parse("services:\n  web:\n    image: nginx\n")

        // Without it the container lands on the runtime's global network, where unrelated
        // projects can reach each other.
        #expect(ComposeOrchestrator.networksToCreate(composeFile: compose, projectName: "proj")
            .map(\.name) == ["proj-default"])
        #expect(ComposeOrchestrator.networksToRemove(composeFile: compose, projectName: "proj")
            == ["proj-default"])
    }

    @Test("No implicit default when every service names a network")
    func noImplicitDefaultWhenAllServicesNameOne() throws {
        let compose = try parse("""
        services:
          web:
            image: nginx
            networks: [backend]
        networks:
          backend:
        """)

        #expect(ComposeOrchestrator.networksToCreate(composeFile: compose, projectName: "proj")
            .map(\.name) == ["proj-backend"])
    }

    @Test("A file's own default: network is used instead of an implicit one")
    func explicitDefaultNetworkWins() throws {
        let compose = try parse("""
        services:
          web:
            image: nginx
        networks:
          default:
            name: shared-default
        """)

        #expect(ComposeOrchestrator.networksToCreate(composeFile: compose, projectName: "proj")
            .map(\.name) == ["shared-default"])
        // The service must join that same network. Resolving it separately from the
        // creation list is how a container ends up asking for a network nobody made.
        #expect(ComposeOrchestrator.networkForService(
            compose.services["web"]!, composeFile: compose, projectName: "proj") == "shared-default")
    }

    @Test("A service joins the network the project actually creates", arguments: [
        ("services:\n  web:\n    image: nginx\n", "proj-default"),
        ("services:\n  web:\n    image: nginx\n    networks: [backend]\nnetworks:\n  backend:\n", "proj-backend"),
        ("services:\n  web:\n    image: nginx\n    networks: [backend]\nnetworks:\n  backend:\n    external: true\n", "backend"),
        ("services:\n  web:\n    image: nginx\nnetworks:\n  default:\n    external: true\n    name: shared-net\n", "shared-net"),
    ])
    func serviceNetworkMatchesCreatedNetwork(yaml: String, expected: String) throws {
        let compose = try parse(yaml)

        #expect(ComposeOrchestrator.networkForService(
            compose.services["web"]!, composeFile: compose, projectName: "proj") == expected)
    }

    @Test("A service's networks: accepts both the list and the mapping form")
    func serviceNetworksBothForms() throws {
        let listForm = try parse("""
        services:
          web:
            image: nginx
            networks: [backend, frontend]
        """)
        let mappingForm = try parse("""
        services:
          web:
            image: nginx
            networks:
              backend:
                aliases: [db]
              frontend:
        """)

        #expect(listForm.services["web"]?.networks == ["backend", "frontend"])
        // The mapping form used to parse as no networks at all, silently leaving the
        // container on the runtime's default network.
        #expect(mappingForm.services["web"]?.networks == ["backend", "frontend"])
    }

    @Test("A service joining an undeclared network is an error")
    func undefinedNetworkReferenceThrows() throws {
        let compose = try parse("""
        services:
          web:
            image: nginx
            networks: [ghost]
        """)

        // Otherwise `up` asks the runtime for a network nothing ever creates.
        #expect(throws: MockerError.self) {
            try compose.validateNetworkReferences()
        }
    }

    @Test("Declared networks pass validation")
    func declaredNetworkReferencesPass() throws {
        let compose = try parse("""
        services:
          web:
            image: nginx
            networks: [backend]
        networks:
          backend:
        """)

        #expect(throws: Never.self) { try compose.validateNetworkReferences() }
    }
}

@Suite("Compose down --rmi")
struct ComposeImageRemovalTests {
    private let compose = try! ComposeFile.parse("""
    services:
      built:
        build: ./built
      pulled:
        image: nginx:1.25
      tagged:
        image: registry.example.com/app:v1
        build: ./app
    """)

    @Test("local removes only what compose built")
    func localOnlyBuiltImages() {
        let images = ComposeOrchestrator.imagesToRemove(
            composeFile: compose, projectName: "proj", mode: .local
        )

        #expect(images == ["proj-built:latest"])
    }

    @Test("all removes every image the services reference")
    func allIncludesPulledImages() {
        let images = ComposeOrchestrator.imagesToRemove(
            composeFile: compose, projectName: "proj", mode: .all
        )

        #expect(images == ["proj-built:latest", "nginx:1.25", "registry.example.com/app:v1"])
    }

    @Test("A tag shared by two services is removed once")
    func deduplicatesSharedTags() throws {
        let shared = try ComposeFile.parse("""
        services:
          a:
            image: shared:1
          b:
            image: shared:1
        """)

        #expect(ComposeOrchestrator.imagesToRemove(
            composeFile: shared, projectName: "proj", mode: .all
        ) == ["shared:1"])
    }
}
