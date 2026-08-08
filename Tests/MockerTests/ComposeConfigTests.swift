import Testing
import Foundation
import MockerKit
@testable import Mocker

/// `mocker compose config` is meant to show the resolved configuration that `up`
/// will actually apply. Before this fix it silently dropped `mem_limit` and
/// `deploy.resources.limits/reservations` — the exact "compose mem_limit stripped"
/// complaint in #62 — even though `ComposeOrchestrator.startService` already wires
/// `service.memLimit` into the container's `-m` flag. These tests lock in that the
/// printed config now reflects the resource limits that get applied.
@Suite("Compose Config Tests")
struct ComposeConfigTests {

    @Test("compose config prints mem_limit as deploy.resources.limits.memory")
    func composeConfigPrintsMemLimit() throws {
        let composeFile = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
            mem_limit: 2g
        """)

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: "proj")

        #expect(output.contains("deploy:"))
        #expect(output.contains("limits:"))
        #expect(output.contains("memory: 2g"))
    }

    @Test("compose config prints deploy.resources.limits.cpus and reservations")
    func composeConfigPrintsDeployResources() throws {
        let composeFile = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
            deploy:
              resources:
                limits:
                  cpus: "0.50"
                  memory: 512M
                reservations:
                  cpus: "0.25"
                  memory: 256M
        """)

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: "proj")

        #expect(output.contains("cpus: \"0.50\""))
        #expect(output.contains("memory: 512M"))
        #expect(output.contains("reservations:"))
        #expect(output.contains("cpus: \"0.25\""))
        #expect(output.contains("memory: 256M"))
    }

    @Test("compose config omits deploy block when no resource limits are set")
    func composeConfigOmitsDeployWhenUnset() throws {
        let composeFile = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
        """)

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: "proj")

        #expect(!output.contains("deploy:"))
    }

    @Test("compose config prints the resolved project name, not the literal 'default'")
    func composeConfigPrintsResolvedName() throws {
        let composeFile = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
        """)

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: "myproj")

        #expect(output.hasPrefix("name: myproj"))
        #expect(!output.contains("name: default"))
    }

    @Test("Service selection matches the exact service, not a name substring")
    func serviceSelectionIsExact() {
        let web = ContainerInfo(
            id: "1", name: "proj-web-1", image: "nginx", state: .running, status: "running",
            created: Date(), labels: ["com.mocker.compose.project": "proj",
                                      "com.mocker.compose.service": "web"]
        )
        let webhook = ContainerInfo(
            id: "2", name: "proj-webhook-1", image: "nginx", state: .running, status: "running",
            created: Date(), labels: ["com.mocker.compose.project": "proj",
                                      "com.mocker.compose.service": "webhook"]
        )

        #expect(ComposeOrchestrator.belongs(web, to: "web", projectName: "proj"))
        #expect(!ComposeOrchestrator.belongs(webhook, to: "web", projectName: "proj"))
    }

    @Test("An unlabeled container is never claimed by a project")
    func unlabeledContainersAreOutOfScope() {
        // Naming alone cannot tell project `app` + service `prod-web` apart from project
        // `app-prod` + service `web`, and down/restart remove what they select.
        let unlabeled = ContainerInfo(id: "3", name: "proj-web-1", image: "nginx", state: .running, status: "running", created: Date())

        #expect(!ComposeOrchestrator.belongs(unlabeled, toProject: "proj"))
        #expect(!ComposeOrchestrator.belongs(unlabeled, to: "web", projectName: "proj"))
    }

    @Test("compose build tags images <project>-<service>, never the bare service name")
    func buildPlanUsesProjectPrefixedTag() throws {
        let compose = try ComposeFile.parse("""
        services:
          caddy:
            build:
              context: ./caddy
          api:
            image: registry.example.com/api:v1
            build:
              context: ./api
          nobuild:
            image: nginx:latest
        """)

        let plan = ComposeBuildCommand.buildPlan(composeFile: compose, project: "laradock", services: [])

        #expect(plan.map(\.name) == ["api", "caddy"])
        // An explicit image: is the tag; otherwise the project-prefixed default.
        #expect(plan.map(\.tag) == ["registry.example.com/api:v1", "laradock-caddy:latest"])
    }

    @Test("compose build honors the requested service subset")
    func buildPlanFiltersServices() throws {
        let compose = try ComposeFile.parse("""
        services:
          web:
            build:
              context: ./web
          worker:
            build:
              context: ./worker
        """)

        let plan = ComposeBuildCommand.buildPlan(composeFile: compose, project: "proj", services: ["worker"])

        #expect(plan.map(\.tag) == ["proj-worker:latest"])
    }

    @Test("A sibling project's containers are never in scope")
    func projectScopingIsExact() {
        let sibling = ContainerInfo(
            id: "5", name: "app-prod-web-1", image: "nginx", state: .running, status: "running",
            created: Date(), labels: ["com.mocker.compose.project": "app-prod",
                                      "com.mocker.compose.service": "web"]
        )
        let own = ContainerInfo(
            id: "6", name: "app-web-1", image: "nginx", state: .running, status: "running",
            created: Date(), labels: ["com.mocker.compose.project": "app",
                                      "com.mocker.compose.service": "web"]
        )

        #expect(!ComposeOrchestrator.belongs(sibling, toProject: "app"))
        #expect(ComposeOrchestrator.belongs(own, toProject: "app"))
        #expect(!ComposeOrchestrator.belongs(sibling, to: "web", projectName: "app"))
        #expect(ComposeOrchestrator.belongs(own, to: "web", projectName: "app"))
    }

    @Test("compose config renders build: as Compose long form, not a Swift description")
    func composeConfigRendersBuildSection() throws {
        let compose = try ComposeFile.parse("""
        services:
          api:
            build:
              context: ./api
              dockerfile: Dockerfile.dev
              args:
                VERSION: "1.2"
        """)

        let output = ComposeConfig.renderConfig(composeFile: compose, projectName: "proj")

        #expect(output.contains("    build:"))
        #expect(output.contains("      context: ./api"))
        #expect(output.contains("      dockerfile: Dockerfile.dev"))
        #expect(output.contains("        VERSION: 1.2"))
        #expect(!output.contains("ComposeBuild("))
    }

    @Test("compose config renders environment as KEY=value, not a Swift tuple")
    func composeConfigRendersEnvironment() throws {
        let compose = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
            environment:
              - FOO=bar
              - "NOTE=has # hash"
        """)

        let output = ComposeConfig.renderConfig(composeFile: compose, projectName: "proj")

        #expect(output.contains("      - FOO=bar"))
        #expect(!output.contains("(key:"))
        // A `#` would start a YAML comment if left bare.
        #expect(output.contains("      - \"NOTE=has # hash\""))
    }

    @Test("config output stays valid YAML for values that would break it")
    func composeConfigOutputRoundTrips() throws {
        let compose = try ComposeFile.parse("""
        services:
          app:
            image: nginx:latest
            environment:
              - "NOTE=has # hash"
              - "URL=http://example.com:8080"
        """)

        let output = ComposeConfig.renderConfig(composeFile: compose, projectName: "proj")
        let reparsed = try ComposeFile.parse(output)

        #expect(reparsed.services["app"]?.environment["NOTE"] == "has # hash")
        #expect(reparsed.services["app"]?.environment["URL"] == "http://example.com:8080")
    }
}
