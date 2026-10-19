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
        #expect(ComposeOrchestrator.networksForService(
            compose.services["web"]!, composeFile: compose, projectName: "proj") == ["shared-default"])
    }

    @Test("A service joins the network the project actually creates", arguments: [
        ("services:\n  web:\n    image: nginx\n", "proj-default"),
        ("services:\n  web:\n    image: nginx\n    networks: [backend]\nnetworks:\n  backend:\n", "proj-backend"),
        ("services:\n  web:\n    image: nginx\n    networks: [backend]\nnetworks:\n  backend:\n    external: true\n", "backend"),
        ("services:\n  web:\n    image: nginx\nnetworks:\n  default:\n    external: true\n    name: shared-net\n", "shared-net"),
    ])
    func serviceNetworkMatchesCreatedNetwork(yaml: String, expected: String) throws {
        let compose = try parse(yaml)

        #expect(ComposeOrchestrator.networksForService(
            compose.services["web"]!, composeFile: compose, projectName: "proj") == [expected])
    }

    @Test("A service joins every network it names, in its order")
    func serviceJoinsAllNetworks() throws {
        let compose = try parse("""
        services:
          api:
            image: nginx
            networks: [front, back]
        networks:
          front:
          back:
            external: true
        """)

        #expect(ComposeOrchestrator.networksForService(
            compose.services["api"]!, composeFile: compose, projectName: "proj") == ["proj-front", "back"])
    }

    @Test("Two keys naming one runtime network join it once")
    func serviceNetworksDeduplicated() throws {
        let compose = try parse("""
        services:
          api:
            image: nginx
            networks: [front, alias]
        networks:
          front:
            name: shared
          alias:
            name: shared
        """)

        #expect(ComposeOrchestrator.networksForService(
            compose.services["api"]!, composeFile: compose, projectName: "proj") == ["shared"])
    }

    @Test("Reconcile keeps a container whose recorded networks match, recreates one that joined fewer")
    func reconcileComparesAllNetworks() throws {
        let compose = try parse("""
        services:
          api:
            image: nginx
            networks: [front, back]
        networks:
          front:
          back:
        """)
        let hash = ComposeService.hash(of: compose.services["api"]!)
        func decision(_ label: String) -> ReconcileAction.Kind? {
            ComposeOrchestrator.reconcileDecision(
                observedContainers: [ObservedContainer(
                    name: "proj-api-1", serviceName: "api", configHash: hash, network: label)],
                composeFile: compose, projectName: "proj", forceRecreate: false, noRecreate: false
            ).first?.kind
        }

        #expect(decision("proj-front,proj-back") == .keep)
        // An earlier release recorded (and joined) only the first network.
        #expect(decision("proj-front") == .removeAndRecreate)
    }

    @Test("Hosts entries use the address on a shared network and skip isolated peers")
    func hostsAddressPicksSharedNetwork() {
        func info(_ addresses: [String: String]?, joined: String = "", primary: String = "") -> ContainerInfo {
            ContainerInfo(
                id: "c", name: "c", image: "i", state: .running, status: "Up", created: Date(),
                labels: ["com.mocker.compose.network": joined],
                networkAddress: primary, networkAddresses: addresses)
        }
        let web = info(["front": "10.0.0.2"], joined: "front", primary: "10.0.0.2")
        let api = info(["front": "10.0.0.3", "back": "10.0.1.3"], joined: "front,back", primary: "10.0.0.3")
        let db = info(["back": "10.0.1.4"], joined: "back", primary: "10.0.1.4")

        #expect(ComposeOrchestrator.hostsAddress(of: api, for: db) == "10.0.1.3")
        #expect(ComposeOrchestrator.hostsAddress(of: api, for: web) == "10.0.0.3")
        #expect(ComposeOrchestrator.hostsAddress(of: db, for: web) == nil)
        // Several shared networks pick by the target's join order, not by name.
        let both = info(["front": "10.0.0.9", "back": "10.0.1.9"], joined: "front,back")
        #expect(ComposeOrchestrator.hostsAddress(of: api, for: both) == "10.0.0.3")
        // Records from before per-network addresses keep the primary address, unless their
        // recorded network is one the target is not on.
        #expect(ComposeOrchestrator.hostsAddress(
            of: info(nil, joined: "back", primary: "10.0.1.7"), for: db) == "10.0.1.7")
        #expect(ComposeOrchestrator.hostsAddress(
            of: info(nil, joined: "back", primary: "10.0.1.7"), for: web) == nil)
    }

    @Test("A stored container record from before per-network addresses still decodes")
    func oldContainerRecordDecodes() throws {
        let json = """
        {"id":"a","name":"a","image":"alpine","state":"running","status":"Up",
         "created":0,"ports":[],"labels":{},"command":"","networkAddress":"10.0.0.1"}
        """
        let decoded = try JSONDecoder().decode(ContainerInfo.self, from: Data(json.utf8))
        #expect(decoded.networkAddresses == nil)
        #expect(decoded.networkAddress == "10.0.0.1")
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
