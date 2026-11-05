import CryptoKit
import Foundation

/// A dotted version such as "1.2" or "1.2.3" (a leading "v" is allowed). 1.1 and 1.1.0 are equal.
public struct Version: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var rest = Substring(text)
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        let pieces = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        parts = numbers
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}

/// A published release that can be installed: where its zip is and the SHA-256 it must have.
public struct Release: Equatable {
    public let tag: String
    public let version: Version
    public let pageURL: URL
    public let zipURL: URL
    public let zipSize: Int
    public let sha256: String // lowercase hex

    public init(tag: String, version: Version, pageURL: URL, zipURL: URL, zipSize: Int, sha256: String) {
        self.tag = tag
        self.version = version
        self.pageURL = pageURL
        self.zipURL = zipURL
        self.zipSize = zipSize
        self.sha256 = sha256
    }
}

public enum UpdateError: Error, Equatable, LocalizedError {
    case badResponse(String)
    case notAStableRelease
    case noDownload
    case badDigest
    case untrustedURL
    case downloadFailed

    public var errorDescription: String? {
        switch self {
        case .badResponse(let why): return "GitHub's answer could not be understood (\(why))."
        case .notAStableRelease: return "The latest release is a draft or pre-release."
        case .noDownload: return "The latest release has no LangCycle zip to install."
        case .badDigest: return "The latest release does not publish a SHA-256 fingerprint for its zip."
        case .untrustedURL: return "The release points at a download location that is not this project's GitHub releases."
        case .downloadFailed: return "The download did not complete."
        }
    }
}

/// Reads the JSON GitHub returns for `GET /repos/<repo>/releases/latest` and returns the release to install.
/// Refuses anything it cannot fully trust: the zip must be named `LangCycle-<version>.zip`, live under this
/// repository's own release downloads on github.com over https, and come with a published sha256 digest.
public func parseLatestRelease(_ data: Data, repo: String) throws -> Release {
    struct API: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int
            let digest: String?
            let browserDownloadUrl: String
        }
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let htmlUrl: String
        let assets: [Asset]
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let api: API
    do { api = try decoder.decode(API.self, from: data) } catch { throw UpdateError.badResponse("not a release") }
    guard !api.draft, !api.prerelease else { throw UpdateError.notAStableRelease }
    guard api.tagName.hasPrefix("v"), let version = Version(api.tagName) else {
        throw UpdateError.badResponse("unexpected tag '\(api.tagName.prefix(30))'")
    }

    let zipName = "LangCycle-\(api.tagName.dropFirst()).zip"
    guard let asset = api.assets.first(where: { $0.name == zipName }), (1...200_000_000).contains(asset.size) else {
        throw UpdateError.noDownload
    }
    guard let digest = asset.digest, digest.hasPrefix("sha256:") else { throw UpdateError.badDigest }
    let hex = String(digest.dropFirst("sha256:".count)).lowercased()
    guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { throw UpdateError.badDigest }

    guard let zipURL = URL(string: asset.browserDownloadUrl), zipURL.scheme == "https", zipURL.host == "github.com",
          zipURL.path.hasPrefix("/\(repo)/releases/download/\(api.tagName)/"),
          let pageURL = URL(string: api.htmlUrl), pageURL.scheme == "https", pageURL.host == "github.com",
          pageURL.path.hasPrefix("/\(repo)/") else { throw UpdateError.untrustedURL }

    return Release(tag: api.tagName, version: version, pageURL: pageURL, zipURL: zipURL, zipSize: asset.size, sha256: hex)
}

/// True when the last check is at least `interval` ago (or never happened, or lies in the future).
public func isUpdateCheckDue(last: Date?, now: Date, interval: TimeInterval = 24 * 60 * 60) -> Bool {
    guard let last, last <= now else { return true }
    return now.timeIntervalSince(last) >= interval
}

/// SHA-256 of a file as lowercase hex, read in chunks.
public func sha256Hex(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
