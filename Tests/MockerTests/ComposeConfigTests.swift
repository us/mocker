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

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: nil)

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

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: nil)

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

        let output = ComposeConfig.renderConfig(composeFile: composeFile, projectName: nil)

        #expect(!output.contains("deploy:"))
    }
}
