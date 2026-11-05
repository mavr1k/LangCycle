import Foundation

public enum InstallError: Error, Equatable, LocalizedError {
    case digestMismatch
    case unzipFailed(String)
    case unexpectedContents
    case wrongBundleID(String?)
    case wrongVersion(String?)
    case badSignature(String)
    case replaceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .digestMismatch: return "The downloaded file does not match the published SHA-256 fingerprint, so it was not installed."
        case .unzipFailed(let why): return "The download could not be unpacked (\(why))."
        case .unexpectedContents: return "The download does not contain exactly one LangCycle.app."
        case .wrongBundleID(let id): return "The downloaded app has an unexpected identifier (\(id ?? "none"))."
        case .wrongVersion(let v): return "The downloaded app is version \(v ?? "unknown"), not the version that was announced."
        case .badSignature(let why): return "The downloaded app's signature is not valid (\(why))."
        case .replaceFailed(let why): return "The current app could not be replaced (\(why))."
        }
    }
}

/// Installs a downloaded release zip over the running app. Does nothing to the current app unless every
/// check passes: the zip's SHA-256 must equal the published one, it must unpack to exactly one `LangCycle.app`
/// with the expected bundle identifier and version, and (normally) a valid code signature. The swap itself is
/// done with `replaceItemAt`, which keeps the old app in place if anything goes wrong.
public enum AppInstaller {
    public static func install(zip: URL, expectedSHA256: String, expectedVersion: Version, bundleID: String,
                               replacing app: URL, verifySignature: Bool = true) throws {
        guard try sha256Hex(of: zip) == expectedSHA256.lowercased() else { throw InstallError.digestMismatch }

        // A folder on the same volume as the app, so the final swap is a rename and not a copy.
        let fileManager = FileManager.default
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? fileManager.removeItem(at: staging) }

        let unzip = run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        guard unzip.status == 0 else { throw InstallError.unzipFailed(unzip.output) }
        guard (try? fileManager.contentsOfDirectory(atPath: staging.path)) == ["LangCycle.app"] else {
            throw InstallError.unexpectedContents
        }
        let newApp = staging.appendingPathComponent("LangCycle.app")

        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == bundleID else {
            throw InstallError.wrongBundleID(info?["CFBundleIdentifier"] as? String)
        }
        let packagedVersion = info?["CFBundleShortVersionString"] as? String
        guard let packagedVersion, Version(packagedVersion) == expectedVersion else {
            throw InstallError.wrongVersion(packagedVersion)
        }
        if verifySignature {
            let check = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            guard check.status == 0 else { throw InstallError.badSignature(check.output) }
        }

        do { _ = try fileManager.replaceItemAt(app, withItemAt: newApp) } catch {
            throw InstallError.replaceFailed(error.localizedDescription)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile() // read before waiting, or a full pipe would block
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, String(text.prefix(300)))
    }
}
