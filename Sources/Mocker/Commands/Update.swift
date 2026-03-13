import ArgumentParser
import MockerKit
import Foundation

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update configuration of one or more containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    @Option(name: .shortAndLong, help: "Memory limit (e.g. 512m, 1g)")
    var memory: String?

    @Option(name: .long, help: "Number of CPUs")
    var cpus: String?

    @Option(name: [.customShort("c"), .customLong("cpu-shares")], help: "CPU shares (relative weight)")
    var cpuShares: Int?

    @Option(name: .long, help: "Restart policy to apply")
    var restart: String?

    @Option(name: .customLong("pids-limit"), help: "Tune container pids limit (-1 for unlimited)")
    var pidsLimit: Int?

    @Option(name: .customLong("blkio-weight"), help: "Block IO (relative weight), between 10 and 1000, or 0 to disable")
    var blkioWeight: Int?

    @Option(name: .customLong("cpu-period"), help: "Limit CPU CFS (Completely Fair Scheduler) period")
    var cpuPeriod: Int?

    @Option(name: .customLong("cpu-quota"), help: "Limit CPU CFS (Completely Fair Scheduler) quota")
    var cpuQuota: Int?

    @Option(name: .customLong("cpu-rt-period"), help: "Limit CPU real-time period in microseconds")
    var cpuRtPeriod: Int?

    @Option(name: .customLong("cpu-rt-runtime"), help: "Limit CPU real-time runtime in microseconds")
    var cpuRtRuntime: Int?

    @Option(name: .customLong("cpuset-cpus"), help: "CPUs in which to allow execution (0-3, 0,1)")
    var cpusetCpus: String?

    @Option(name: .customLong("cpuset-mems"), help: "MEMs in which to allow execution (0-3, 0,1)")
    var cpusetMems: String?

    @Option(name: .customLong("memory-reservation"), help: "Memory soft limit")
    var memoryReservation: String?

    @Option(name: .customLong("memory-swap"), help: "Swap limit equal to memory plus swap: -1 to enable unlimited swap")
    var memorySwap: String?

    func run() async throws {
        // Accept the flags for compatibility but warn if not applicable
        for identifier in containers {
            print(identifier)
        }
        if memory != nil || cpus != nil {
            FileHandle.standardError.write(Data("WARNING: Resource limits are managed at VM level with Apple Containerization\n".utf8))
        }
    }
}
