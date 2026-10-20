import Foundation
import Testing
@testable import Mocker

@Suite("info --format Tests")
struct InfoFormatTests {
    private let object = SystemInfo.infoObject(containers: 5, running: 2, paused: 1, images: 7, dataRoot: "/root")

    @Test("{{.ServerVersion}} renders the mocker version")
    func serverVersion() throws {
        #expect(try GoTemplate.render("{{.ServerVersion}}", object: object) == Version.currentVersion)
    }

    @Test("container counts are split into running, paused and stopped")
    func counts() throws {
        let out = try GoTemplate.render("{{.Containers}} {{.ContainersRunning}} {{.ContainersPaused}} {{.ContainersStopped}} {{.Images}}", object: object)
        #expect(out == "5 2 1 2 7")
    }

    @Test("{{.NCPU}} and {{.MemTotal}} render as integers")
    func numbers() throws {
        #expect(try GoTemplate.render("{{.NCPU}}", object: object) == "\(ProcessInfo.processInfo.processorCount)")
        #expect(try GoTemplate.render("{{.MemTotal}}", object: object) == "\(ProcessInfo.processInfo.physicalMemory)")
    }

    @Test("top-level info and system info parse --format")
    func parsing() throws {
        let top = try Info.parse(["--format", "{{.ServerVersion}}"])
        #expect(top.format == "{{.ServerVersion}}")
        let sys = try SystemInfo.parse(["-f", "json"])
        #expect(sys.format == "json")
    }

    @Test("mocker info is a registered subcommand")
    func registered() {
        #expect(MockerCLI.configuration.subcommands.contains { $0 == Info.self })
    }
}
