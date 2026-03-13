import ArgumentParser

struct ImageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "image",
        abstract: "Manage images",
        subcommands: [
            Images.self,
            Build.self,
            Pull.self,
            Push.self,
            Tag.self,
            Rmi.self,
            History.self,
            Save.self,
            Load.self,
            Import.self,
            ImageRm.self,
            ImageInspect.self,
            ImagePrune.self,
        ],
        defaultSubcommand: Images.self
    )
}
