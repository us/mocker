import ArgumentParser

@main
struct MockerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mocker",
        abstract: "Docker-compatible container management tool built on Apple Containerization",
        version: Version.currentVersion,
        subcommands: [
            Run.self,
            Create.self,
            Start.self,
            PS.self,
            Stop.self,
            Restart.self,
            Kill.self,
            Wait.self,
            Remove.self,
            Exec.self,
            Logs.self,
            Build.self,
            Pull.self,
            Push.self,
            Images.self,
            Tag.self,
            Rmi.self,
            Inspect.self,
            Stats.self,
            Login.self,
            Logout.self,
            Version.self,
            Cp.self,
            Attach.self,
            Rename.self,
            Port.self,
            Top.self,
            Diff.self,
            Pause.self,
            Unpause.self,
            Update.self,
            History.self,
            Save.self,
            Load.self,
            Export.self,
            Commit.self,
            Import.self,
            Search.self,
            ContainerCommand.self,
            ImageCommand.self,
            ManifestCommand.self,
            NetworkCommand.self,
            VolumeCommand.self,
            ComposeCommand.self,
            SystemCommand.self,
            Proxy.self,
            Serve.self,
        ]
    )

    /// Custom entry point that preprocesses argv before ArgumentParser sees it.
    /// Docker-style global compose flags placed before the subcommand
    /// (`compose -f a.yaml pull`) are relocated to after the subcommand token,
    /// since ArgumentParser only parses a subcommand's options after that token.
    /// See `ComposeArgNormalizer`.
    static func main() async {
        let argv = ComposeArgNormalizer.reorder(Array(CommandLine.arguments.dropFirst()))
        do {
            var command = try parseAsRoot(argv)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}
