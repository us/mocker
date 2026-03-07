import ArgumentParser

@main
struct MockerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mocker",
        abstract: "Docker-compatible container management tool built on Apple Containerization",
        version: "0.1.0",
        subcommands: [
            Run.self,
            PS.self,
            Stop.self,
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
            NetworkCommand.self,
            VolumeCommand.self,
            ComposeCommand.self,
            SystemCommand.self,
        ]
    )
}
