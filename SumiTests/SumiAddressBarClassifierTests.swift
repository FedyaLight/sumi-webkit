import XCTest

@testable import Sumi

/// Parity corpus for the native address-bar classifier, ported from the
/// vendored DDG URLPredictor reference tests (macOS policy) before the Rust
/// dependency was removed.
final class SumiAddressBarClassifierTests: XCTestCase {
    private func assertNavigate(
        _ input: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .navigate(let url) = SumiAddressBarClassifier.classify(input) else {
            XCTFail("expected navigate for \(input)", file: file, line: line)
            return
        }
        XCTAssertEqual(url.absoluteString, expected, file: file, line: line)
    }

    private func assertSearch(
        _ input: String, _ expected: String? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .search(let query) = SumiAddressBarClassifier.classify(input) else {
            XCTFail("expected search for \(input)", file: file, line: line)
            return
        }
        XCTAssertEqual(query, expected ?? input.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
    }

    func testBareDomainsNavigate() {
        assertNavigate("regular-domain.com/path/to/directory/", "http://regular-domain.com/path/to/directory/")
        assertNavigate("regular-domain.com", "http://regular-domain.com/")
        assertNavigate("regular-domain.com/", "http://regular-domain.com/")
        assertNavigate("regular-domain.com/filename", "http://regular-domain.com/filename")
        assertNavigate("regular-domain.com/filename?a=b&b=c", "http://regular-domain.com/filename?a=b&b=c")
        assertNavigate("apple.com/mac/", "http://apple.com/mac/")
        assertNavigate("duckduckgo.com", "http://duckduckgo.com/")
        assertNavigate("www.duckduckgo.com", "http://www.duckduckgo.com/")
        assertNavigate(" duckduckgo.com", "http://duckduckgo.com/")
        assertNavigate("regular-domain.com/path/to/file ", "http://regular-domain.com/path/to/file")
    }

    func testIntranetMultiLabelHostsNavigate() {
        // macOS policy: multi-label hosts navigate without consulting the PSL.
        assertNavigate("stuff.stor", "http://stuff.stor/")
        assertNavigate("stuff.store", "http://stuff.store/")
        assertNavigate("windows.applicationmodel.store.dll", "http://windows.applicationmodel.store.dll/")
    }

    func testSearchPhrases() {
        assertSearch("one two three")
        assertSearch("search string with spaces")
        assertSearch("test string with spaces")
        assertSearch("define: foo")
        assertSearch(" duck duck go.c ", "duck duck go.c")
        assertSearch("local ", "local")
        assertSearch("localdomain")
        assertSearch("duckduckgo")
        assertSearch("1+(3+4*2)")
        assertSearch("16385-12228.72")
        assertSearch("1.4/3.4")
        assertSearch("1.2")
        assertSearch("1.2.7")
        assertSearch("test://hello/")
    }

    func testExplicitSchemesPreserved() {
        assertNavigate("http://regular-domain.com?a=b&b=c", "http://regular-domain.com/?a=b&b=c")
        assertNavigate("http://regular-domain.com/?a=b&b=c", "http://regular-domain.com/?a=b&b=c")
        assertNavigate("https://hexfiend.com/file?q=a", "https://hexfiend.com/file?q=a")
        assertNavigate("https://hexfiend.com/?q=a", "https://hexfiend.com/?q=a")
        assertNavigate("https://hexfiend.com?q=a", "https://hexfiend.com/?q=a")
        assertNavigate("   http://example.com\n", "http://example.com/")
        assertNavigate("https://www.duckduckgo.com", "https://www.duckduckgo.com/")
    }

    func testSpacesInsideExplicitURLsArePercentEncoded() {
        assertNavigate(
            "https://duckduckgo.com/?q=search string with spaces&arg 2=val 2",
            "https://duckduckgo.com/?q=search%20string%20with%20spaces&arg%202=val%202"
        )
        assertNavigate(
            "https://duckduckgo.com/?q=search+string+with+spaces",
            "https://duckduckgo.com/?q=search+string+with+spaces"
        )
        assertNavigate(
            "https://screwjankgames.github.io/engine programming/2020/09/24/writing-your.html",
            "https://screwjankgames.github.io/engine%20programming/2020/09/24/writing-your.html"
        )
        assertNavigate(
            "http://user name:pass word@domain.com/folder name/file name/",
            "http://user%20name:pass%20word@domain.com/folder%20name/file%20name/"
        )
    }

    func testInternationalizedHostsArePunycoded() {
        assertNavigate("https://例子.测试", "https://xn--fsqu00a.xn--0zwm56d/")
        assertNavigate(
            "https://example.com/пример/测试",
            "https://example.com/%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/%E6%B5%8B%E8%AF%95"
        )
        assertNavigate("http://💩.la:8080 ", "http://xn--ls8h.la:8080/")
        assertNavigate("https://xn--ls8h.la/path/to/resource", "https://xn--ls8h.la/path/to/resource")
        assertSearch("http:// 💩.la:8080 ", "http:// 💩.la:8080")
    }

    func testLocalhostAndIPv4() {
        assertNavigate("localhost ", "http://localhost/")
        assertNavigate("localhost:8080", "http://localhost:8080/")
        assertNavigate("127.0.0.1", "http://127.0.0.1/")
        assertNavigate("http://127.0.0.1", "http://127.0.0.1/")
        // URL-standard shorthand expansion applies only with an explicit scheme.
        assertNavigate("http://1.2.7", "http://1.2.0.7/")
    }

    func testUserinfoHeuristics() {
        assertSearch("user@localhost")
        assertSearch("user@domain.com")
        assertSearch("user: @domain.com")
        assertNavigate("http://user@domain.com", "http://user@domain.com/")
        assertNavigate("http://user: @domain.com", "http://user:%20@domain.com/")
        assertNavigate("http://user:,,@domain.com", "http://user:,,@domain.com/")
        assertNavigate("http://user:pass@domain.com", "http://user:pass@domain.com/")
        assertNavigate("user:pass@domain.com", "http://user:pass@domain.com/")
        assertNavigate("user:,,@domain.com", "http://user:,,@domain.com/")
        assertNavigate("user:::@domain.com", "http://user:%3A%3A@domain.com/")
        assertNavigate("https://user@domain.com", "https://user@domain.com/")
        assertNavigate("https://user:pass@domain.com", "https://user:pass@domain.com/")
        // Empty password drops the dangling separator.
        assertNavigate("http://user:@domain.com", "http://user@domain.com/")
    }

    func testMissingSlashAfterSchemeIsRepaired() {
        assertNavigate("http:/duckduckgo.com", "http://duckduckgo.com/")
        assertNavigate("http:/example.com", "http://example.com/")
        assertNavigate("https:/duckduckgo.com", "https://duckduckgo.com/")
        assertNavigate("file:/Users/user/file.txt", "file:///Users/user/file.txt")
        assertNavigate("file://domain/file.txt", "file://domain/file.txt")
        assertNavigate("file:///Users/user/file.txt", "file:///Users/user/file.txt")
    }

    func testNonHTTPAllowedSchemesNavigate() {
        assertNavigate("mailto:user@example.com", "mailto:user@example.com")
        assertNavigate("about:blank", "about:blank")
        assertNavigate("sumi://newtab", "sumi://newtab")
        assertNavigate("webkit-extension://sample-extension", "webkit-extension://sample-extension")
    }
}

final class SumiPublicSuffixListTests: XCTestCase {
    func testWildcardAndExceptionRules() {
        let list = SumiPublicSuffixList(listText: """
        // comment
        com
        co.uk
        *.ck
        !www.ck
        """)

        XCTAssertEqual(list.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(list.registrableDomain(forHost: "multi.part.bbc.co.uk"), "bbc.co.uk")
        // *.ck makes bar.ck a public suffix, so foo.bar.ck is registrable.
        XCTAssertEqual(list.registrableDomain(forHost: "foo.bar.ck"), "foo.bar.ck")
        XCTAssertNil(list.registrableDomain(forHost: "bar.ck"))
        // !www.ck exempts www.ck from the wildcard.
        XCTAssertEqual(list.registrableDomain(forHost: "www.ck"), "www.ck")
        XCTAssertEqual(list.registrableDomain(forHost: "sub.www.ck"), "www.ck")
        XCTAssertNil(list.registrableDomain(forHost: "unknown.tld-not-listed"))
        XCTAssertNil(list.registrableDomain(forHost: "com"))
    }

    func testBundledListResolvesPrivateSuffixes() {
        let list = SumiPublicSuffixList.bundled
        XCTAssertEqual(list.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(list.registrableDomain(forHost: "myapp.github.io"), "myapp.github.io")
        XCTAssertTrue(list.isPublicSuffix("github.io"))
        XCTAssertTrue(list.isPublicSuffix("co.uk"))
        XCTAssertFalse(list.isPublicSuffix("example.com"))
    }
}
