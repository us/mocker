import Foundation
import Testing
@testable import Mocker

@Suite("GoTemplate inspect --format Tests")
struct GoTemplateTests {
    /// A Docker-shaped container inspect record, mirroring `mapToContainerInspect`
    /// output (PascalCase keys, nested `State`/`Config`/`NetworkSettings`).
    private func runningContainer() -> [String: Any] {
        [
            "Id": "probe",
            "Name": "/probe",
            "Image": "postgres:16-alpine",
            "Config": ["Image": "postgres:16-alpine"],
            "NetworkSettings": ["IPAddress": "192.168.64.3"],
            "State": [
                "Running": true,
                "Paused": false,
                "Status": "running",
                "Pid": 1234,
            ],
        ]
    }

    // MARK: - The dev-stand health gate

    @Test("{{.State.Running}} renders bare true for a running container")
    func stateRunningTrue() throws {
        #expect(try GoTemplate.render("{{.State.Running}}", object: runningContainer()) == "true")
    }

    @Test("{{.State.Running}} renders bare false for a stopped container")
    func stateRunningFalse() throws {
        var c = runningContainer()
        c["State"] = ["Running": false, "Status": "exited"]
        #expect(try GoTemplate.render("{{.State.Running}}", object: c) == "false")
    }

    @Test("{{.State.Status}} renders the lifecycle string")
    func stateStatus() throws {
        #expect(try GoTemplate.render("{{.State.Status}}", object: runningContainer()) == "running")
    }

    @Test("{{.State.Pid}} renders an integer without a decimal point")
    func statePid() throws {
        #expect(try GoTemplate.render("{{.State.Pid}}", object: runningContainer()) == "1234")
    }

    @Test("{{.Id}} resolves the container id")
    func idResolves() throws {
        #expect(try GoTemplate.render("{{.Id}}", object: runningContainer()) == "probe")
    }

    @Test("{{.Name}} resolves the slash-prefixed name")
    func nameResolves() throws {
        #expect(try GoTemplate.render("{{.Name}}", object: runningContainer()) == "/probe")
    }

    @Test("{{.Config.Image}} resolves the image reference")
    func configImage() throws {
        #expect(try GoTemplate.render("{{.Config.Image}}", object: runningContainer()) == "postgres:16-alpine")
    }

    @Test("{{.NetworkSettings.IPAddress}} resolves the container IP")
    func networkIP() throws {
        #expect(try GoTemplate.render("{{.NetworkSettings.IPAddress}}", object: runningContainer()) == "192.168.64.3")
    }

    // MARK: - Whitespace, literals, multiple tokens

    @Test("whitespace inside the braces is tolerated")
    func whitespaceTolerated() throws {
        #expect(try GoTemplate.render("{{ .State.Running }}", object: runningContainer()) == "true")
    }

    @Test("surrounding literal text is preserved")
    func literalTextPreserved() throws {
        #expect(try GoTemplate.render("status={{.State.Status}}!", object: runningContainer()) == "status=running!")
    }

    @Test("multiple tokens in one template all resolve")
    func multipleTokens() throws {
        #expect(try GoTemplate.render("{{.Id}} {{.State.Running}}", object: runningContainer()) == "probe true")
    }

    @Test("a template with no tokens is returned verbatim")
    func noTokensVerbatim() throws {
        #expect(try GoTemplate.render("just literal text", object: runningContainer()) == "just literal text")
    }

    // MARK: - Edge cases

    @Test("unknown path renders empty, not the literal token")
    func unknownPathEmpty() throws {
        #expect(try GoTemplate.render("{{.Nope.Missing}}", object: runningContainer()) == "")
    }

    @Test("a value containing braces does not retrigger substitution")
    func noReentrantSubstitution() throws {
        var c = runningContainer()
        c["Name"] = "{{.State.Running}}"
        #expect(try GoTemplate.render("{{.Name}}", object: c) == "{{.State.Running}}")
    }

    // MARK: - Real encode path (JSONSerialization bridges bools to NSNumber)

    @Test("booleans survive the JSON encode/decode round-trip as true/false")
    func boolRoundTripThroughJSON() throws {
        // The CLI feeds GoTemplate a dict produced by JSONSerialization, where JSON
        // booleans arrive as NSNumber. Exercise that exact path, not just native Bool.
        let json = #"{"State":{"Running":true,"Status":"running"}}"#
        let data = Data(json.utf8)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(try GoTemplate.render("{{.State.Running}}", object: object) == "true")
        #expect(try GoTemplate.render("{{.State.Status}}", object: object) == "running")
    }

    // MARK: - Multi-token isolation and scalar edge cases

    @Test("a token's resolved value never re-triggers a later token's substitution")
    func multiTokenNoCrossSubstitution() throws {
        // The first token's value is the *literal text* of the second token. A naive
        // global replace on a mutated buffer would re-substitute it; range-splicing
        // emits it verbatim.
        let object: [String: Any] = ["A": "{{.B}}", "B": "x"]
        #expect(try GoTemplate.render("{{.A}}-{{.B}}", object: object) == "{{.B}}-x")
    }

    @Test("integer 0 (stopped container Pid) renders 0, and Running renders false")
    func statePidZeroOnStoppedContainer() throws {
        // The CFBoolean type-id check must run before the integer branch so that an
        // integer 0 is not mis-rendered as `false` (and a bool false not as `0`).
        let json = #"{"State":{"Running":false,"Pid":0,"Status":"exited"}}"#
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(try GoTemplate.render("{{.State.Pid}}", object: object) == "0")
        #expect(try GoTemplate.render("{{.State.Running}}", object: object) == "false")
    }

    @Test("an array/object leaf renders empty (documented scope limit, not Docker's [..])")
    func arrayLeafRendersEmpty() throws {
        // Unlike `docker inspect -f '{{.RepoTags}}'` (which prints `[nginx:latest]`),
        // this subset renders a container/array leaf as empty. Pin the behavior so the
        // intentional limitation can't silently regress.
        #expect(try GoTemplate.render("{{.RepoTags}}", object: ["RepoTags": ["nginx:latest"]]) == "")
    }

    // MARK: - Unsupported constructs fail loudly (never silent wrong output)

    @Test("unsupported template actions throw instead of passing through as literal")
    func unsupportedActionsThrow() {
        let c = runningContainer()
        #expect(throws: GoTemplateError.self) { try GoTemplate.render("{{if .State.Running}}y{{end}}", object: c) }
        #expect(throws: GoTemplateError.self) { try GoTemplate.render("{{range .X}}{{end}}", object: c) }
        #expect(throws: GoTemplateError.self) { try GoTemplate.render("{{json .Config}}", object: c) }
        #expect(throws: GoTemplateError.self) { try GoTemplate.render(#"{{index .Config "Image"}}"#, object: c) }
        // A bare `{{.}}` (whole-object identity) is outside the field-path subset.
        #expect(throws: GoTemplateError.self) { try GoTemplate.render("{{.}}", object: c) }
        // A valid field token sitting next to an unsupported action still fails the whole render.
        #expect(throws: GoTemplateError.self) { try GoTemplate.render("{{.Id}} {{range .X}}{{end}}", object: c) }
    }
}
