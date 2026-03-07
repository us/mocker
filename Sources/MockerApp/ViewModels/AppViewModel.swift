import Foundation
import MockerKit
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var containers: [ContainerInfo] = []
    @Published var images: [ImageInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: Tab = .containers

    enum Tab: String, CaseIterable {
        case containers = "Containers"
        case images = "Images"
        case compose = "Compose"
    }

    private let config = MockerConfig()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let engine = try ContainerEngine(config: config)
            containers = try await engine.list(all: true)

            let imageManager = try ImageManager(config: config)
            images = try await imageManager.list()

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopContainer(_ id: String) async {
        do {
            let engine = try ContainerEngine(config: config)
            _ = try await engine.stop(id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeContainer(_ id: String) async {
        do {
            let engine = try ContainerEngine(config: config)
            _ = try await engine.remove(id, force: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pullImage(_ reference: String) async {
        do {
            let imageManager = try ImageManager(config: config)
            _ = try await imageManager.pull(reference)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
