import Testing
import Foundation
import CryptoKit
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

    @Test("Merge overlays later files over earlier ones")
    func mergeOverlay() throws {
        let base = try ComposeFile.parse("""
        services:
          web:
            image: nginx:latest
            environment:
              A: "1"
              B: "1"
        """)
        let overlay = try ComposeFile.parse("""
        services:
          web:
            image: nginx:alpine
            environment:
              B: "2"
          db:
            image: postgres:16
        """)

        let merged = ComposeFile.merge([base, overlay])

        // Later file wins on scalars; new service is added.
        #expect(merged.services["web"]?.image == "nginx:alpine")
        #expect(merged.services["db"]?.image == "postgres:16")
        // environment is field-merged with later winning on conflict.
        #expect(merged.services["web"]?.environment["A"] == "1")
        #expect(merged.services["web"]?.environment["B"] == "2")
    }

    @Test("Merge of a single file returns it unchanged")
    func mergeSingle() throws {
        let only = try ComposeFile.parse("""
        services:
          web:
            image: nginx:latest
        """)
        let merged = ComposeFile.merge([only])
        #expect(merged.services.count == 1)
        #expect(merged.services["web"]?.image == "nginx:latest")
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

    @Test("Parse build.target (issue #14)")
    func parseBuildTarget() throws {
        let yaml = """
        services:
          app:
            build:
              context: .
              target: base
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.build?.target == "base")
    }

    @Test("Parse build.args map form")
    func parseBuildArgsMap() throws {
        let yaml = """
        services:
          app:
            build:
              context: .
              args:
                REQUIRED_TOKEN: secret
                BUILD_ENV: prod
        """

        let compose = try ComposeFile.parse(yaml)
        let args = compose.services["app"]?.build?.args ?? [:]
        #expect(args["REQUIRED_TOKEN"] == "secret")
        #expect(args["BUILD_ENV"] == "prod")
    }

    @Test("Parse build.args list form, preserving explicit empty value")
    func parseBuildArgsList() throws {
        // After variable substitution, `${REQUIRED_TOKEN-}` resolves to an empty
        // value — the key must still be present with an empty string, not dropped.
        let yaml = """
        services:
          app:
            build:
              context: .
              args:
                - BUILD_ENV=prod
                - REQUIRED_TOKEN=
        """

        let compose = try ComposeFile.parse(yaml)
        let args = compose.services["app"]?.build?.args ?? [:]
        #expect(args["BUILD_ENV"] == "prod")
        #expect(args["REQUIRED_TOKEN"] == "")
    }

    @Test("Parse service with both image and build (issue #14 comment)")
    func parseImageAndBuild() throws {
        let yaml = """
        services:
          app:
            image: repro-app
            build:
              context: .
              target: base
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.image == "repro-app")
        #expect(compose.services["app"]?.build?.target == "base")
    }

    // MARK: - Resource limits

    @Test("Parse legacy mem_limit")
    func parseMemLimit() throws {
        let yaml = """
        services:
          app:
            image: nginx
            mem_limit: 512m
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.memLimit == "512m")
    }

    @Test("Parse legacy cpus as fractional")
    func parseCpusFractional() throws {
        let yaml = """
        services:
          app:
            image: nginx
            cpus: 0.5
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.cpus == "0.5")
    }

    @Test("Parse legacy cpus as string")
    func parseCpusString() throws {
        let yaml = """
        services:
          app:
            image: nginx
            cpus: "0.50"
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.cpus == "0.50")
    }

    @Test("Parse legacy mem_reservation")
    func parseMemReservation() throws {
        let yaml = """
        services:
          app:
            image: nginx
            mem_reservation: 256m
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.memReservation == "256m")
    }

    @Test("Parse legacy memswap_limit")
    func parseMemswapLimit() throws {
        let yaml = """
        services:
          app:
            image: nginx
            memswap_limit: 1g
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.memSwapLimit == "1g")
    }

    @Test("Parse legacy shm_size")
    func parseShmSize() throws {
        let yaml = """
        services:
          app:
            image: nginx
            shm_size: 256m
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.shmSize == "256m")
    }

    @Test("Parse legacy pids_limit")
    func parsePidsLimit() throws {
        let yaml = """
        services:
          app:
            image: nginx
            pids_limit: 100
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.pidsLimit == 100)
    }

    @Test("Parse deploy.resources.limits")
    func parseDeployResourcesLimits() throws {
        let yaml = """
        services:
          app:
            image: nginx
            deploy:
              resources:
                limits:
                  cpus: "0.50"
                  memory: 512M
                  pids: 50
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.cpus == "0.50")
        #expect(compose.services["app"]?.memLimit == "512M")
        #expect(compose.services["app"]?.pidsLimit == 50)
    }

    @Test("Parse deploy.resources.reservations")
    func parseDeployResourcesReservations() throws {
        let yaml = """
        services:
          app:
            image: nginx
            deploy:
              resources:
                reservations:
                  cpus: "0.25"
                  memory: 256M
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.cpusReservation == "0.25")
        #expect(compose.services["app"]?.memReservation == "256M")
    }

    @Test("Parse deploy.resources.limits overrides legacy mem_limit")
    func parseDeployOverridesLegacy() throws {
        let yaml = """
        services:
          app:
            image: nginx
            mem_limit: 256m
            deploy:
              resources:
                limits:
                  memory: 512M
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.memLimit == "512M")
    }

    @Test("Parse deploy.resources.limits.pids overrides legacy pids_limit")
    func parseDeployPidsOverridesLegacy() throws {
        let yaml = """
        services:
          app:
            image: nginx
            pids_limit: 100
            deploy:
              resources:
                limits:
                  pids: 200
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.pidsLimit == 200)
    }

    @Test("Parse all resource limits together")
    func parseAllResourceLimits() throws {
        let yaml = """
        services:
          app:
            image: nginx
            mem_limit: 512m
            mem_reservation: 256m
            memswap_limit: 1g
            cpus: 2
            shm_size: 128m
            pids_limit: 200
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.memLimit == "512m")
        #expect(compose.services["app"]?.memReservation == "256m")
        #expect(compose.services["app"]?.memSwapLimit == "1g")
        #expect(compose.services["app"]?.cpus == "2")
        #expect(compose.services["app"]?.shmSize == "128m")
        #expect(compose.services["app"]?.pidsLimit == 200)
    }

    @Test("Resource limits merge: later overlay wins")
    func mergeResourceLimits() throws {
        let base = try ComposeFile.parse("""
        services:
          app:
            image: nginx
            mem_limit: 256m
            cpus: 1
            shm_size: 64m
        """)
        let overlay = try ComposeFile.parse("""
        services:
          app:
            mem_limit: 512m
            shm_size: 128m
        """)

        let merged = ComposeFile.merge([base, overlay])
        #expect(merged.services["app"]?.memLimit == "512m")
        #expect(merged.services["app"]?.cpus == "1", "cpus not in overlay, keep base value")
        #expect(merged.services["app"]?.shmSize == "128m")
    }

    @Test("Parse deploy.restart_policy overrides legacy restart")
    func parseDeployRestartPolicy() throws {
        let yaml = """
        services:
          app:
            image: nginx
            restart: always
            deploy:
              restart_policy:
                condition: on-failure
                delay: 5s
                max_attempts: 3
                window: 120s
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.restart == "on-failure")
        #expect(compose.services["app"]?.restartPolicyDelay == "5s")
        #expect(compose.services["app"]?.restartPolicyMaxAttempts == 3)
        #expect(compose.services["app"]?.restartPolicyWindow == "120s")
    }

    @Test("Parse deploy.restart_policy only, no legacy restart")
    func parseDeployRestartPolicyOnly() throws {
        let yaml = """
        services:
          app:
            image: nginx
            deploy:
              restart_policy:
                condition: any
                delay: 10s
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.restart == "always", "any → always")
        #expect(compose.services["app"]?.restartPolicyDelay == "10s")
        #expect(compose.services["app"]?.restartPolicyMaxAttempts == nil)
    }

    @Test("deploy.restart_policy condition none maps to no")
    func parseDeployRestartPolicyNone() throws {
        let yaml = """
        services:
          app:
            image: nginx
            deploy:
              restart_policy:
                condition: none
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.restart == "no")
    }

    @Test("Legacy restart used when no deploy.restart_policy")
    func parseLegacyRestartWhenNoDeploy() throws {
        let yaml = """
        services:
          app:
            image: nginx
            restart: unless-stopped
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.restart == "unless-stopped")
        #expect(compose.services["app"]?.restartPolicyDelay == nil)
    }

    @Test("restart_policy without condition keeps legacy restart")
    func parseRestartPolicyNoConditionKeepsLegacy() throws {
        let yaml = """
        services:
          app:
            image: nginx
            restart: always
            deploy:
              restart_policy:
                delay: 5s
        """

        let compose = try ComposeFile.parse(yaml)
        #expect(compose.services["app"]?.restart == "always")
        #expect(compose.services["app"]?.restartPolicyDelay == "5s")
    }

    @Test("Restart policy merge: later overlay wins")
    func mergeRestartPolicy() throws {
        let base = try ComposeFile.parse("""
        services:
          app:
            image: nginx
            deploy:
              restart_policy:
                condition: on-failure
                delay: 5s
                max_attempts: 3
        """)
        let overlay = try ComposeFile.parse("""
        services:
          app:
            deploy:
              restart_policy:
                condition: any
                delay: 10s
                window: 60s
        """)

        let merged = ComposeFile.merge([base, overlay])
        #expect(merged.services["app"]?.restart == "always", "any → always")
        #expect(merged.services["app"]?.restartPolicyDelay == "10s")
        #expect(merged.services["app"]?.restartPolicyMaxAttempts == 3, "max_attempts not in overlay, keep base")
        #expect(merged.services["app"]?.restartPolicyWindow == "60s")
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

    @Test("Explicit --project-directory wins over -f dir and cwd")
    func resolveProjectDirectoryExplicitWins() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: "/tmp/sub",
            files: ["/tmp/sub/dir/compose.yml"],
            cwd: "/tmp/other"
        )
        #expect(resolved.path == "/tmp/sub")
    }

    @Test("First -f directory wins when no explicit flag")
    func resolveProjectDirectoryFirstFileWins() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["/tmp/sub/dir/compose.yml"],
            cwd: "/tmp/other"
        )
        #expect(resolved.path == "/tmp/sub/dir")
    }

    @Test("Empty explicit --project-directory is treated as absent, falls through to -f dir")
    func resolveProjectDirectoryEmptyExplicitFallsThrough() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: "",
            files: ["/tmp/dir/x.yml"],
            cwd: "/tmp/other"
        )
        #expect(resolved.path == "/tmp/dir")
    }

    @Test("CWD wins when no explicit flag and no -f files")
    func resolveProjectDirectoryCWDFallback() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: [],
            cwd: "/tmp/myproject"
        )
        #expect(resolved.path == "/tmp/myproject")
    }

    @Test("Nonexistent explicit project-directory is accepted lazily")
    func resolveProjectDirectoryLazyValidation() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: "/no/exist/path",
            files: ["/tmp/proj/compose.yml"],
            cwd: "/tmp/other"
        )
        #expect(resolved.path == "/no/exist/path")
        #expect(resolved.lastPathComponent == "path")
    }

    @Test("Single -f - (stdin only) falls back to cwd")
    func resolveProjectDirectoryStdinOnlyFallsBackToCWD() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["-"],
            cwd: "/tmp/x"
        )
        #expect(resolved.path == "/tmp/x")
    }

    @Test("Mixed -f - -f file.yml resolves to the real file's dir (stdin first)")
    func resolveProjectDirectoryMixedStdinFirst() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["-", "/tmp/dir/file.yml"],
            cwd: "/tmp/other"
        )
        #expect(resolved.path == "/tmp/dir")
    }

    @Test("Mixed -f file.yml -f - resolves to the real file's dir (stdin last)")
    func resolveProjectDirectoryMixedStdinLast() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["/tmp/dir/file.yml", "-"],
            cwd: "/tmp/other"
        )
        #expect(resolved.path == "/tmp/dir")
    }

    @Test("All -f entries are - falls back to cwd")
    func resolveProjectDirectoryAllStdinFallsBackToCWD() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["-", "-"],
            cwd: "/tmp/x"
        )
        #expect(resolved.path == "/tmp/x")
    }

    @Test("Relative explicit --project-directory resolves against injected cwd, not process cwd")
    func resolveProjectDirectoryRelativeExplicitHonorsCwd() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: "sub",
            files: [],
            cwd: "/tmp/myproject"
        )
        #expect(resolved.path == "/tmp/myproject/sub")
    }

    @Test("Relative first -f entry resolves against injected cwd, not process cwd")
    func resolveProjectDirectoryRelativeFirstFileHonorsCwd() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["dir/compose.yml"],
            cwd: "/tmp/myproject"
        )
        #expect(resolved.path == "/tmp/myproject/dir")
    }

    @Test("Injected cwd different from the real process cwd is honored")
    func resolveProjectDirectoryHonorsInjectedCwdOverProcessCwd() {
        let resolved = ComposeFile.resolveProjectDirectory(
            explicit: "relative",
            files: [],
            cwd: "/tmp/not-the-real-cwd"
        )
        #expect(resolved.path == "/tmp/not-the-real-cwd/relative")
        #expect(resolved.path != FileManager.default.currentDirectoryPath + "/relative")
    }

    @Test("Explicit flag + deeper compose file: name from flag's last component, not the file's parent")
    func projectNameFromExplicitFlagNotFileParent() {
        let projectDir = ComposeFile.resolveProjectDirectory(
            explicit: "/tmp/myproj",
            files: ["/tmp/myproj/deep/sub/compose.yml"],
            cwd: "/tmp/other"
        )
        #expect(projectDir.lastPathComponent != "sub")
        #expect(ComposeFile.normalizeProjectName(projectDir.lastPathComponent) == "myproj")
    }

    @Test("No flag, deeper compose file: name from first -f dir's last component")
    func projectNameFromFirstFileDirWhenNoFlag() {
        let projectDir = ComposeFile.resolveProjectDirectory(
            explicit: nil,
            files: ["/tmp/myproj/deep/sub/compose.yml"],
            cwd: "/tmp/other"
        )
        #expect(ComposeFile.normalizeProjectName(projectDir.lastPathComponent) == "sub")
    }

    @Test("normalizeProjectName lowercases uppercase directory names")
    func normalizeProjectNameLowercasesUppercase() {
        #expect(ComposeFile.normalizeProjectName("MyProject") == "myproject")
    }

    @Test("normalizeProjectName replaces spaces with dashes")
    func normalizeProjectNameReplacesSpaces() {
        #expect(ComposeFile.normalizeProjectName("my project") == "my-project")
    }

    private static let substitutionYAML = """
    services:
      web:
        image: alpine:${TAG:-fallback}
    """

    @Test(".env loaded from projectDir, not the compose file's own dir")
    func envLoadedFromProjectDir() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("sub/dir/compose.yml", Self.substitutionYAML),
            .file("sub/dir/.env", "TAG=from_dir\n"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let composePath = root.appendingPathComponent("sub/dir/compose.yml").path
        let projectDir = root.appendingPathComponent("sub/dir")
        let compose = try ComposeFile.load(from: composePath, projectDir: projectDir)
        #expect(compose.services["web"]?.image == "alpine:from_dir")
    }

    @Test("Explicit project-directory overrides .env source over first -f dir")
    func envSourceFollowsExplicitProjectDirectory() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("sub/dir/compose.yml", Self.substitutionYAML),
            .file("sub/.env", "TAG=from_sub\n"),
            .file("sub/dir/.env", "TAG=from_dir\n"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let composePath = root.appendingPathComponent("sub/dir/compose.yml").path
        let projectDir = root.appendingPathComponent("sub")
        let compose = try ComposeFile.load(from: composePath, projectDir: projectDir)
        #expect(compose.services["web"]?.image == "alpine:from_sub")
    }

    @Test("CWD's .env is not loaded when project-dir is established via -f")
    func envNotLoadedFromCWDWhenProjectDirFromFile() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("sub/dir/compose.yml", Self.substitutionYAML),
            .file("sub/dir/.env", "TAG=from_dir\n"),
            .file("cwd/.env", "TAG=from_cwd\n"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let composePath = root.appendingPathComponent("sub/dir/compose.yml").path
        let projectDir = root.appendingPathComponent("sub/dir")
        let compose = try ComposeFile.load(from: composePath, projectDir: projectDir)
        #expect(compose.services["web"]?.image == "alpine:from_dir")
    }

    @Test("Missing .env is silently skipped, no error")
    func missingEnvSilentlySkipped() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("proj/compose.yml", Self.substitutionYAML),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let composePath = root.appendingPathComponent("proj/compose.yml").path
        let projectDir = root.appendingPathComponent("proj")
        let compose = try ComposeFile.load(from: composePath, projectDir: projectDir)
        #expect(compose.services["web"]?.image == "alpine:fallback")
    }

    @Test("Env var in build.context substituted, then resolved against project-dir")
    func buildContextEnvVarSubstitutedThenResolved() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("proj/compose.yml", """
                services:
                  app:
                    build:
                      context: "${MYDIR}"
                """),
            .file("proj/.env", "MYDIR=./sub/app\n"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let composePath = root.appendingPathComponent("proj/compose.yml").path
        let projectDir = root.appendingPathComponent("proj")
        let compose = try ComposeFile.load(from: composePath, projectDir: projectDir)

        // Substitution already ran during load() — the raw "${MYDIR}" literal is gone.
        #expect(compose.services["app"]?.build?.context == "./sub/app")

        let absContext = ImageManager.resolveContextPath(
            context: compose.services["app"]!.build!.context, cwd: projectDir.path
        )
        #expect(absContext == projectDir.appendingPathComponent("sub/app").path)
    }

    @Test("Env var resolving to absolute path passes through unchanged after substitution")
    func buildContextEnvVarAbsolutePassesThroughUnchanged() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("proj/compose.yml", """
                services:
                  app:
                    build:
                      context: "${MYDIR}"
                """),
            .file("proj/.env", "MYDIR=/absolute/path/to/context\n"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let composePath = root.appendingPathComponent("proj/compose.yml").path
        let projectDir = root.appendingPathComponent("proj")
        let compose = try ComposeFile.load(from: composePath, projectDir: projectDir)

        #expect(compose.services["app"]?.build?.context == "/absolute/path/to/context")

        let absContext = ImageManager.resolveContextPath(
            context: compose.services["app"]!.build!.context, cwd: projectDir.path
        )
        #expect(absContext == "/absolute/path/to/context")
    }

    @Test("load(content:): valid YAML string parses like a file")
    func loadContentStdinHappyPath() throws {
        let root = try ComposeTestHelpers.makeProjectDir([])
        defer { try? FileManager.default.removeItem(at: root) }

        let projectDir = root.appendingPathComponent("sliceb_sa", isDirectory: true)
        let yaml = """
        services:
          web:
            image: alpine
        """
        let compose = try ComposeFile.load(content: yaml, projectDir: projectDir)
        #expect(compose.services["web"]?.image == "alpine")
    }

    @Test("load(content:): empty string throws composeParseError with empty detail")
    func loadContentEmptyStdinThrows() throws {
        let root = try ComposeTestHelpers.makeProjectDir([])
        defer { try? FileManager.default.removeItem(at: root) }

        let projectDir = root.appendingPathComponent("sliceb_sb", isDirectory: true)
        #expect(throws: MockerError.self) {
            _ = try ComposeFile.load(content: "", projectDir: projectDir)
        }
        do {
            _ = try ComposeFile.load(content: "", projectDir: projectDir)
            Issue.record("expected throw")
        } catch let error as MockerError {
            #expect(error.errorDescription?.contains("compose file content is empty") == true)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("load(content:): whitespace-only content throws the same empty-stdin error")
    func loadContentWhitespaceOnlyStdinThrows() throws {
        let root = try ComposeTestHelpers.makeProjectDir([])
        defer { try? FileManager.default.removeItem(at: root) }

        let projectDir = root.appendingPathComponent("sliceb_sc", isDirectory: true)
        do {
            _ = try ComposeFile.load(content: "  \n\n  ", projectDir: projectDir)
            Issue.record("expected throw")
        } catch let error as MockerError {
            #expect(error.errorDescription?.contains("compose file content is empty") == true)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // MARK: - Config hash (issue #59)

    @Test("ComposeService.hash returns sha256:<64 hex chars> for a fixed spec")
    func hashReturnsSha256Literal() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
            environment:
              FOO: bar
        """).services["app"]!

        let hash = ComposeService.hash(of: svc)

        #expect(hash.hasPrefix("sha256:"))
        #expect(hash.count == "sha256:".count + 64)
        let hex = String(hash.dropFirst("sha256:".count))
        #expect(hex.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("ComposeService.hash is stable across equivalent service specs (different field order)")
    func hashIsDeterministicAcrossFieldOrder() throws {
        let first = try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
            environment:
              FOO: bar
              BAZ: qux
            ports:
              - "8080:80"
        """).services["app"]!
        let second = try ComposeFile.parse("""
        services:
          app:
            ports:
              - "8080:80"
            environment:
              BAZ: qux
              FOO: bar
            image: nginx:alpine
        """).services["app"]!

        #expect(ComposeService.hash(of: first) == ComposeService.hash(of: second))
    }

    @Test("ComposeService.hash ignores Docker-normalized fields (build, dependsOn)")
    func hashIgnoresNormalizedFields() throws {
        let withoutBuild = try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
        """).services["app"]!
        let withBuild = try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
            build:
              context: .
              dockerfile: Dockerfile.dev
            depends_on:
              - db
        """).services["app"]!

        #expect(ComposeService.hash(of: withoutBuild) == ComposeService.hash(of: withBuild))
    }

    @Test("ComposeService.encode emits only hash-relevant fields (no build/dependsOn)")
    func encodeProducesOnlyHashRelevantFields() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
            build:
              context: .
            depends_on:
              - db
        """).services["app"]!

        let data = try JSONEncoder().encode(svc)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["build"] == nil)
        #expect(json["depends_on"] == nil)
        #expect(json["name"] as? String == "app")
        #expect(json["image"] as? String == "nginx:alpine")
    }

    @Test("ComposeService.hash(of:) equals sha256 of JSONEncoder.encode(service) with sortedKeys")
    func hashEqualsSHA256OfEncodedJSON() throws {
        let svc = try ComposeFile.parse("""
        services:
          app:
            image: nginx:alpine
            environment:
              FOO: bar
        """).services["app"]!

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let expectedHex = SHA256.hash(data: try encoder.encode(svc))
            .map { String(format: "%02x", $0) }.joined()

        #expect(ComposeService.hash(of: svc) == "sha256:" + expectedHex)
    }

    @Test("ComposeService.hash is deterministic for the same input")
    func hashDeterministicForSameInput() throws {
        let svc = try ComposeFile.parse("services:\n  app:\n    image: nginx:alpine\n")
            .services["app"]!
        let hash = ComposeService.hash(of: svc)
        #expect(hash.hasPrefix("sha256:"))
        #expect(hash.count == "sha256:".count + 64)
        #expect(ComposeService.hash(of: svc) == hash)
    }
}
