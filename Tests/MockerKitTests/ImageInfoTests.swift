import Testing
@testable import MockerKit

@Suite("ImageInfo short ID")
struct ImageInfoTests {

    @Test("shortID is 12 hex digits without the sha256: prefix, like `docker images -q`")
    func shortIDStripsDigestPrefix() {
        let info = ImageInfo(
            id: "sha256:7f57cb92185e478bbdafc89b7b88ffabcc91e1ae95aef63ea46646610c313b3b",
            repository: "alpine"
        )
        #expect(info.shortID == "7f57cb92185e")
    }

    @Test("shortID of a bare digest is its first 12 characters")
    func shortIDBareDigest() {
        #expect(ImageInfo(id: "abc123def456789", repository: "x").shortID == "abc123def456")
        #expect(ImageInfo.shortID(of: "sha256:abcdef") == "abcdef")
    }
}
