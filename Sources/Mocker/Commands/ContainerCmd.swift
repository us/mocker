import ArgumentParser

struct ContainerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "container",
        abstract: "Manage containers",
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
            Inspect.self,
            Stats.self,
            Attach.self,
            Rename.self,
            Port.self,
            Top.self,
            Diff.self,
            Pause.self,
            Unpause.self,
            Update.self,
            Cp.self,
            Export.self,
            Commit.self,
            ContainerPrune.self,
        ],
        defaultSubcommand: PS.self
    )
}
