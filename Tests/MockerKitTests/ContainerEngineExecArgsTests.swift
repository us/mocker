import Testing
@testable import MockerKit

/// `ContainerEngine.makeExecArguments` — the pure argument-vector builder behind
/// `mocker exec`. Every Docker flag mocker accepts must reach `container exec`,
/// and all options must precede the container name.
@Suite("ContainerEngine exec arguments")
struct ContainerEngineExecArgsTests {

    @Test("env, env-file, user, workdir and detach are forwarded before the name")
    func flagsForwarded() {
        let args = ContainerEngine.makeExecArguments(
            name: "web", command: ["printenv"], interactive: true, tty: true, detach: true,
            env: ["FOO=bar", "HOME"], envFiles: ["/tmp/a.env"], user: "nobody", workdir: "/tmp"
        )
        let nameIndex = args.firstIndex(of: "web")!
        #expect(args.first == "exec")
        #expect(args.last == "printenv")
        for flag in ["-i", "-t", "-d", "-e", "--env-file", "-u", "-w"] {
            #expect(args.firstIndex(of: flag)! < nameIndex, "\(flag) must precede the container name")
        }
        #expect(adjacent(args, "-e", "FOO=bar"))
        #expect(adjacent(args, "-e", "HOME"))
        #expect(adjacent(args, "--env-file", "/tmp/a.env"))
        #expect(adjacent(args, "-u", "nobody"))
        #expect(adjacent(args, "-w", "/tmp"))
    }

    private func adjacent(_ args: [String], _ flag: String, _ value: String) -> Bool {
        for (i, a) in args.enumerated() where a == flag {
            if i + 1 < args.count, args[i + 1] == value { return true }
        }
        return false
    }
}
