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
}
