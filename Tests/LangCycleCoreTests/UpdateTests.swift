import Foundation
import Testing
@testable import LangCycleCore

// MARK: Version

@Test func versionsCompareNumerically() throws {
    #expect(try #require(Version("1.1")) < #require(Version("1.1.1")))
    #expect(try #require(Version("1.9.3")) < #require(Version("1.10")))  // not alphabetical
    #expect(try #require(Version("v2.0")) > #require(Version("1.99.99")))
    #expect(try #require(Version("1.1")) == #require(Version("1.1.0")))  // missing parts count as 0
    #expect(try #require(Version("v1.2")) == #require(Version("1.2")))
    #expect(try #require(Version("1.2.3")).description == "1.2.3")
}

@Test(arguments: ["", "v", "1.", ".1", "1..2", "1.x", "1.2-beta", "1.2.3.4.5", "١.٢", "99999999999999999999.1", " 1.2"])
func malformedVersionsAreRejected(text: String) {
    #expect(Version(text) == nil)
}

// MARK: Parsing GitHub's answer

private let repo = "mavr1k/LangCycle"
private let goodDigest = "sha256:2144d1e414d05d33341aa9418a57ccc57eee170bcbcccca6933b6d9f672460c0"

/// A release JSON shaped like GitHub's, with each interesting field adjustable.
private func releaseJSON(tag: String = "v1.2", draft: Bool = false, prerelease: Bool = false,
                         page: String = "https://github.com/mavr1k/LangCycle/releases/tag/v1.2",
                         assetName: String = "LangCycle-1.2.zip", size: Int = 2_040_521,
                         digest: String? = goodDigest,
                         url: String = "https://github.com/mavr1k/LangCycle/releases/download/v1.2/LangCycle-1.2.zip") -> Data {
    var asset: [String: Any] = ["name": assetName, "size": size, "browser_download_url": url]
    if let digest { asset["digest"] = digest }
    let object: [String: Any] = ["tag_name": tag, "draft": draft, "prerelease": prerelease, "html_url": page,
                                 "body": "notes", "assets": [asset]]
    return try! JSONSerialization.data(withJSONObject: object)
}

@Test func aGoodReleaseIsParsed() throws {
    let release = try parseLatestRelease(releaseJSON(), repo: repo)
    #expect(release.tag == "v1.2")
    #expect(release.version == Version("1.2"))
    #expect(release.zipURL.absoluteString == "https://github.com/mavr1k/LangCycle/releases/download/v1.2/LangCycle-1.2.zip")
    #expect(release.pageURL.absoluteString == "https://github.com/mavr1k/LangCycle/releases/tag/v1.2")
    #expect(release.zipSize == 2_040_521)
    #expect(release.sha256 == "2144d1e414d05d33341aa9418a57ccc57eee170bcbcccca6933b6d9f672460c0")
}

@Test func thePatchStyleTagAndUppercaseDigestWork() throws {
    let data = releaseJSON(tag: "v1.1.1", page: "https://github.com/mavr1k/LangCycle/releases/tag/v1.1.1",
                           assetName: "LangCycle-1.1.1.zip", digest: goodDigest.uppercased().replacingOccurrences(of: "SHA256:", with: "sha256:"),
                           url: "https://github.com/mavr1k/LangCycle/releases/download/v1.1.1/LangCycle-1.1.1.zip")
    let release = try parseLatestRelease(data, repo: repo)
    #expect(release.version == Version("1.1.1"))
    #expect(release.sha256 == String(goodDigest.dropFirst(7)))  // normalised to lowercase
}

@Test func unusableOrUntrustedReleasesAreRefused() {
    func parse(_ data: Data) -> UpdateError? {
        do { _ = try parseLatestRelease(data, repo: repo); return nil } catch { return error as? UpdateError }
    }
    #expect(parse(releaseJSON(draft: true)) == .notAStableRelease)
    #expect(parse(releaseJSON(prerelease: true)) == .notAStableRelease)
    #expect(parse(releaseJSON(assetName: "Other.zip")) == .noDownload)
    #expect(parse(releaseJSON(assetName: "LangCycle-9.9.zip")) == .noDownload)       // not this version's zip
    #expect(parse(releaseJSON(size: 0)) == .noDownload)
    #expect(parse(releaseJSON(size: 900_000_000)) == .noDownload)
    #expect(parse(releaseJSON(digest: nil)) == .badDigest)
    #expect(parse(releaseJSON(digest: "md5:abc")) == .badDigest)
    #expect(parse(releaseJSON(digest: "sha256:1234")) == .badDigest)
    #expect(parse(releaseJSON(digest: "sha256:" + String(repeating: "g", count: 64))) == .badDigest)
    // Download location must be this repo's release downloads on github.com over https.
    #expect(parse(releaseJSON(url: "http://github.com/mavr1k/LangCycle/releases/download/v1.2/LangCycle-1.2.zip")) == .untrustedURL)
    #expect(parse(releaseJSON(url: "https://evil.example.com/mavr1k/LangCycle/releases/download/v1.2/LangCycle-1.2.zip")) == .untrustedURL)
    #expect(parse(releaseJSON(url: "https://github.com.evil.example/mavr1k/LangCycle/releases/download/v1.2/LangCycle-1.2.zip")) == .untrustedURL)
    #expect(parse(releaseJSON(url: "https://github.com/someone-else/LangCycle/releases/download/v1.2/LangCycle-1.2.zip")) == .untrustedURL)
    #expect(parse(releaseJSON(url: "https://github.com/mavr1k/LangCycle/releases/download/v1.1/LangCycle-1.2.zip")) == .untrustedURL) // other tag
    #expect(parse(releaseJSON(page: "https://evil.example.com/mavr1k/LangCycle/releases/tag/v1.2")) == .untrustedURL)
    // Not a release at all, or a tag that is not a version.
    #expect(parse(Data("{}".utf8)) != nil)
    #expect(parse(Data("not json".utf8)) != nil)
    #expect(parse(releaseJSON(tag: "latest")) != nil)
    #expect(parse(releaseJSON(tag: "1.2")) != nil)                                 // must be written v1.2
}

// MARK: Schedule and fingerprint

@Test func theCheckIsDueOncePerDay() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    #expect(isUpdateCheckDue(last: nil, now: now))
    #expect(!isUpdateCheckDue(last: now.addingTimeInterval(-3_600), now: now))
    #expect(!isUpdateCheckDue(last: now.addingTimeInterval(-86_399), now: now))
    #expect(isUpdateCheckDue(last: now.addingTimeInterval(-86_400), now: now))
    #expect(isUpdateCheckDue(last: now.addingTimeInterval(-10 * 86_400), now: now))
    #expect(isUpdateCheckDue(last: now.addingTimeInterval(3_600), now: now))      // clock went backwards
    #expect(isUpdateCheckDue(last: now.addingTimeInterval(-600), now: now, interval: 300))
}

@Test func sha256MatchesTheKnownValueForAbc() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("abc-\(UUID().uuidString).txt")
    try Data("abc".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(try sha256Hex(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

// MARK: Installer

/// A scratch folder with helpers to build fake apps and zips; removed when the value is dropped.
private final class Sandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lc-test-\(UUID().uuidString)")
    init() { try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }

    /// Makes `<folder>/LangCycle.app` with an Info.plist and a marker file; returns the app's URL.
    @discardableResult
    func makeApp(in folder: String, version: String, bundleID: String = "com.local.langcycle", marker: String) -> URL {
        let app = root.appendingPathComponent(folder).appendingPathComponent("LangCycle.app")
        let contents = app.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try! (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        try! Data(marker.utf8).write(to: contents.appendingPathComponent("marker"))
        return app
    }

    /// Zips everything inside `folder` (so a stray extra file ends up in the zip too).
    func zip(folder: String) -> URL {
        let source = root.appendingPathComponent(folder)
        let zip = root.appendingPathComponent("\(folder).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", source.path, zip.path]
        try! process.run()
        process.waitUntilExit()
        return zip
    }

    func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8)
    }
}

private let wanted = Version("1.2")!

@Test func theInstallerReplacesTheAppWhenEverythingChecksOut() throws {
    let box = Sandbox()
    let installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    box.makeApp(in: "download", version: "1.2", marker: "new")
    let zip = box.zip(folder: "download")

    try AppInstaller.install(zip: zip, expectedSHA256: try sha256Hex(of: zip), expectedVersion: wanted,
                             bundleID: "com.local.langcycle", replacing: installed, verifySignature: false)

    #expect(box.marker(of: installed) == "new")
    let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    #expect(info?["CFBundleShortVersionString"] as? String == "1.2")
    #expect(FileManager.default.fileExists(atPath: installed.path))
}

@Test func aWrongFingerprintLeavesTheInstalledAppUntouched() throws {
    let box = Sandbox()
    let installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    box.makeApp(in: "download", version: "1.2", marker: "new")
    let zip = box.zip(folder: "download")

    #expect(throws: InstallError.digestMismatch) {
        try AppInstaller.install(zip: zip, expectedSHA256: String(repeating: "0", count: 64), expectedVersion: wanted,
                                 bundleID: "com.local.langcycle", replacing: installed, verifySignature: false)
    }
    #expect(box.marker(of: installed) == "old")
}

@Test func aDownloadThatIsTheWrongAppOrVersionIsRefused() throws {
    // Wrong bundle identifier
    var box = Sandbox()
    var installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    box.makeApp(in: "download", version: "1.2", bundleID: "com.example.other", marker: "new")
    var zip = box.zip(folder: "download")
    #expect(throws: InstallError.wrongBundleID("com.example.other")) {
        try AppInstaller.install(zip: zip, expectedSHA256: try sha256Hex(of: zip), expectedVersion: wanted,
                                 bundleID: "com.local.langcycle", replacing: installed, verifySignature: false)
    }
    #expect(box.marker(of: installed) == "old")

    // The zip holds a different version than the one announced
    box = Sandbox()
    installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    box.makeApp(in: "download", version: "1.0", marker: "new")
    zip = box.zip(folder: "download")
    #expect(throws: InstallError.wrongVersion("1.0")) {
        try AppInstaller.install(zip: zip, expectedSHA256: try sha256Hex(of: zip), expectedVersion: wanted,
                                 bundleID: "com.local.langcycle", replacing: installed, verifySignature: false)
    }
    #expect(box.marker(of: installed) == "old")
}

@Test func aZipWithExtraFilesOrNoAppIsRefused() throws {
    // An extra file next to the app
    var box = Sandbox()
    var installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    box.makeApp(in: "download", version: "1.2", marker: "new")
    try Data("extra".utf8).write(to: box.root.appendingPathComponent("download/README.txt"))
    var zip = box.zip(folder: "download")
    #expect(throws: InstallError.unexpectedContents) {
        try AppInstaller.install(zip: zip, expectedSHA256: try sha256Hex(of: zip), expectedVersion: wanted,
                                 bundleID: "com.local.langcycle", replacing: installed, verifySignature: false)
    }
    #expect(box.marker(of: installed) == "old")

    // Not a zip at all
    box = Sandbox()
    installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    zip = box.root.appendingPathComponent("garbage.zip")
    try Data("this is not a zip".utf8).write(to: zip)
    #expect(throws: (any Error).self) {
        try AppInstaller.install(zip: zip, expectedSHA256: try sha256Hex(of: zip), expectedVersion: wanted,
                                 bundleID: "com.local.langcycle", replacing: installed, verifySignature: false)
    }
    #expect(box.marker(of: installed) == "old")
}

@Test func anUnsignedAppIsRefusedWhenSignaturesAreChecked() throws {
    let box = Sandbox()
    let installed = box.makeApp(in: "installed", version: "1.1", marker: "old")
    box.makeApp(in: "download", version: "1.2", marker: "new")   // a fake app has no valid signature
    let zip = box.zip(folder: "download")

    do {
        try AppInstaller.install(zip: zip, expectedSHA256: try sha256Hex(of: zip), expectedVersion: wanted,
                                 bundleID: "com.local.langcycle", replacing: installed, verifySignature: true)
        Issue.record("the install should have been refused")
    } catch let error as InstallError {
        guard case .badSignature = error else { Issue.record("wrong error: \(error)"); return }
    }
    #expect(box.marker(of: installed) == "old")
}
