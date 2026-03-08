import Testing
import Foundation
@testable import MockerKit

@Suite("ComposeFile Tests")
struct ComposeFileTests {
    @Test("Parse basic compose YAML")
    func parseBasic() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            ports:
              - "8080:80"
          redis:
            image: redis:7
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services.count == 2)
        #expect(compose.services["web"]?.image == "nginx:latest")
        #expect(compose.services["web"]?.ports == ["8080:80"])
        #expect(compose.services["redis"]?.image == "redis:7")
    }

    @Test("Parse compose with environment as list")
    func parseEnvironmentList() throws {
        let yaml = """
        services:
          app:
            image: myapp
            environment:
              - DB_HOST=localhost
              - DB_PORT=5432
        """

        let compose = try ComposeFile.parse(yaml)
        let env = compose.services["app"]?.environment ?? [:]
        #expect(env["DB_HOST"] == "localhost")
        #expect(env["DB_PORT"] == "5432")
    }

    @Test("Parse compose with environment as map")
    func parseEnvironmentMap() throws {
        let yaml = """
        services:
          app:
            image: myapp
            environment:
              DB_HOST: localhost
              DB_PORT: 5432
        """

        let compose = try ComposeFile.parse(yaml)
        let env = compose.services["app"]?.environment ?? [:]
        #expect(env["DB_HOST"] == "localhost")
        #expect(env["DB_PORT"] == "5432")
    }

    @Test("Parse compose with depends_on")
    func parseDependsOn() throws {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              - redis
              - db
          redis:
            image: redis
          db:
            image: postgres
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["web"]?.dependsOn.contains("redis") == true)
        #expect(compose.services["web"]?.dependsOn.contains("db") == true)
    }

    @Test("Service order respects dependencies")
    func serviceOrder() throws {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              - redis
          redis:
            image: redis
        """

        let compose = try ComposeFile.parse(yaml)
        let order = compose.serviceOrder()

        let redisIdx = order.firstIndex(of: "redis")!
        let webIdx = order.firstIndex(of: "web")!
        #expect(redisIdx < webIdx)
    }

    @Test("Parse compose with networks and volumes")
    func parseNetworksAndVolumes() throws {
        let yaml = """
        services:
          web:
            image: nginx
            networks:
              - frontend
            volumes:
              - data:/var/www
        networks:
          frontend:
            driver: bridge
        volumes:
          data:
            driver: local
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.networks["frontend"]?.driver == "bridge")
        #expect(compose.volumes["data"]?.driver == "local")
        #expect(compose.services["web"]?.networks.contains("frontend") == true)
    }

    @Test("Parse compose with build config")
    func parseBuildConfig() throws {
        let yaml = """
        services:
          app:
            build:
              context: ./app
              dockerfile: Dockerfile.dev
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.build?.context == "./app")
        #expect(compose.services["app"]?.build?.dockerfile == "Dockerfile.dev")
    }

    @Test("findDefault returns nil when no compose file exists in empty directory")
    func findDefaultNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        #expect(ComposeFile.findDefault(in: dir) == nil)
    }

    @Test("findDefault finds compose.yml before docker-compose.yml")
    func findDefaultPreferCompose() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let composePath = URL(fileURLWithPath: dir).appendingPathComponent("compose.yml").path
        let dockerComposePath = URL(fileURLWithPath: dir).appendingPathComponent("docker-compose.yml").path
        FileManager.default.createFile(atPath: composePath, contents: Data())
        FileManager.default.createFile(atPath: dockerComposePath, contents: Data())

        let found = ComposeFile.findDefault(in: dir)
        #expect(found == composePath)
    }

    @Test("findDefault finds compose.yaml before compose.yml")
    func findDefaultPreferYaml() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let yamlPath = URL(fileURLWithPath: dir).appendingPathComponent("compose.yaml").path
        let ymlPath = URL(fileURLWithPath: dir).appendingPathComponent("compose.yml").path
        FileManager.default.createFile(atPath: yamlPath, contents: Data())
        FileManager.default.createFile(atPath: ymlPath, contents: Data())

        let found = ComposeFile.findDefault(in: dir)
        #expect(found == yamlPath)
    }

    @Test("findDefault falls back to docker-compose.yml when only it exists")
    func findDefaultFallback() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let path = URL(fileURLWithPath: dir).appendingPathComponent("docker-compose.yml").path
        FileManager.default.createFile(atPath: path, contents: Data())

        let found = ComposeFile.findDefault(in: dir)
        #expect(found == path)
    }

    @Test("defaultFileNames contains expected filenames in correct order")
    func defaultFileNamesOrder() {
        #expect(ComposeFile.defaultFileNames == ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"])
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
}
