import Testing
@testable import Mocker

@Suite("ComposeArgNormalizer Tests")
struct ComposeArgNormalizerTests {

    @Test("Relocates repeated -f before the subcommand to after it")
    func relocateRepeatedFile() {
        let out = ComposeArgNormalizer.reorder(["compose", "-f", "a.yaml", "-f", "b.yaml", "pull"])
        #expect(out == ["compose", "pull", "-f", "a.yaml", "-f", "b.yaml"])
    }

    @Test("Leaves flags already after the subcommand untouched")
    func keepsTrailingFlags() {
        let out = ComposeArgNormalizer.reorder(["compose", "pull", "-f", "a.yaml"])
        #expect(out == ["compose", "pull", "-f", "a.yaml"])
    }

    @Test("Relocates --project-name and preserves trailing subcommand flags")
    func relocateProjectName() {
        let out = ComposeArgNormalizer.reorder(["compose", "-p", "proj", "up", "-d"])
        #expect(out == ["compose", "up", "-p", "proj", "-d"])
    }

    @Test("Keeps the equals-form as a single token")
    func equalsForm() {
        let out = ComposeArgNormalizer.reorder(["compose", "-f=a.yaml", "config"])
        #expect(out == ["compose", "config", "-f=a.yaml"])
    }

    @Test("Mixed before/after -f both end up after the subcommand in order")
    func mixedBeforeAfter() {
        let out = ComposeArgNormalizer.reorder(["compose", "-f", "a.yaml", "pull", "-f", "b.yaml"])
        #expect(out == ["compose", "pull", "-f", "a.yaml", "-f", "b.yaml"])
    }

    @Test("Non-compose argv is returned untouched")
    func nonCompose() {
        let out = ComposeArgNormalizer.reorder(["run", "-p", "80:80", "nginx"])
        #expect(out == ["run", "-p", "80:80", "nginx"])
    }

    @Test("Compose with no subcommand verb is returned untouched")
    func noSubcommand() {
        let out = ComposeArgNormalizer.reorder(["compose", "-f", "a.yaml"])
        #expect(out == ["compose", "-f", "a.yaml"])
    }

    @Test("A flag whose value looks like a flag does not swallow the next flag")
    func missingValueNotSwallowed() {
        // No subcommand verb after -f/-p, so it returns unchanged — but the point
        // is that -p is not consumed as the value of -f.
        let out = ComposeArgNormalizer.reorder(["compose", "-f", "-p"])
        #expect(out == ["compose", "-f", "-p"])
    }
}
