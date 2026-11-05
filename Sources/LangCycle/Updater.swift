import AppKit
import LangCycleCore

/// Checks GitHub for a newer release and, only when the user agrees, installs it (REQUIREMENT.MD, 5.6).
/// The checks that decide what may be installed live in LangCycleCore (parsing, fingerprint, app identity);
/// this class does the network, the schedule, the dialogs and the relaunch.
final class Updater {
    enum Activity { case idle, checking, installing }

    private static let repo = "mavr1k/LangCycle"
    private static let autoKey = "autoUpdateCheck", lastCheckKey = "lastUpdateCheck"

    /// A newer release found by the last check, if any.
    private(set) var available: Release? { didSet { onChange?() } }
    private(set) var activity = Activity.idle { didSet { onChange?() } }
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let current: Version
    private var timer: Timer?

    init() {
        current = Version(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? Version("0")!
    }

    /// "Check for Updates Automatically": on unless the user turned it off.
    var automaticChecks: Bool {
        get { defaults.object(forKey: Self.autoKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.autoKey) }
    }

    // MARK: Schedule

    /// First look shortly after launch, then the schedule is re-read every hour; a check happens at most once a day.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() {
        guard automaticChecks, activity == .idle,
              isUpdateCheckDue(last: defaults.object(forKey: Self.lastCheckKey) as? Date, now: Date()) else { return }
        fetch { _ in }  // automatic checks never open a window; a newer version just appears in the menu
    }

    // MARK: Checking

    /// "Check for Updates Now": always reports what it found.
    func checkNow() {
        fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release?): self.askToInstall(release)
            case .success(nil): self.tell("LangCycle is up to date", "You have the newest version (\(self.current)).")
            case .failure(let error): self.tell("Couldn't check for updates", error.localizedDescription)
            }
        }
    }

    private func fetch(_ completion: @escaping (Result<Release?, Error>) -> Void) {
        guard activity == .idle else { return }
        activity = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LangCycle/\(current)", forHTTPHeaderField: "User-Agent") // GitHub requires one; nothing else is sent
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result = Result<Release, Error> {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse, let data else { throw UpdateError.badResponse("no answer") }
                guard http.statusCode == 200 else { throw UpdateError.badResponse("HTTP \(http.statusCode)") }
                return try parseLatestRelease(data, repo: Self.repo)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.activity = .idle
                switch result {
                case .success(let release):
                    self.defaults.set(Date(), forKey: Self.lastCheckKey)
                    self.available = release.version > self.current ? release : nil // never offers an older or equal version
                    completion(.success(self.available))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: Installing

    /// Asks before doing anything. Nothing is downloaded or replaced unless the user clicks "Install and Restart".
    func askToInstall(_ release: Release) {
        let canInstall = canReplaceThisApp
        activate()
        let alert = NSAlert()
        alert.messageText = "LangCycle \(release.version) is available"
        alert.informativeText = canInstall
            ? "You have \(current). LangCycle will download the update from GitHub, check it against its published SHA-256 fingerprint, replace itself and restart. Your settings are kept."
            : "You have \(current). This copy of LangCycle can't replace itself where it is installed, so download the new version from its release page."
        alert.addButton(withTitle: canInstall ? "Install and Restart" : "Open Release Page")
        alert.addButton(withTitle: "Later")
        if canInstall { alert.addButton(withTitle: "Release Notes") }
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall { install(release) } else { NSWorkspace.shared.open(release.pageURL) }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    /// Only a real, writable .app can be swapped: not a build folder, not a read-only or quarantined location.
    private var canReplaceThisApp: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && !app.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    private func install(_ release: Release) {
        guard activity == .idle else { return }
        activity = .installing
        var request = URLRequest(url: release.zipURL, timeoutInterval: 120)
        request.setValue("LangCycle/\(current)", forHTTPHeaderField: "User-Agent")
        let app = Bundle.main.bundleURL
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.langcycle"
        URLSession.shared.downloadTask(with: request) { [weak self] downloaded, response, error in
            var failure = error
            if failure == nil {
                if let downloaded, (response as? HTTPURLResponse)?.statusCode == 200 {
                    // The system deletes its temporary file when this closure returns, so take it over first.
                    let zip = FileManager.default.temporaryDirectory.appendingPathComponent("LangCycle-update-\(UUID().uuidString).zip")
                    defer { try? FileManager.default.removeItem(at: zip) }
                    do {
                        try FileManager.default.moveItem(at: downloaded, to: zip)
                        try AppInstaller.install(zip: zip, expectedSHA256: release.sha256, expectedVersion: release.version,
                                                 bundleID: bundleID, replacing: app)
                    } catch { failure = error }
                } else {
                    failure = UpdateError.downloadFailed
                }
            }
            DispatchQueue.main.async { self?.finishInstall(release, failure: failure) }
        }.resume()
    }

    private func finishInstall(_ release: Release, failure: Error?) {
        activity = .idle
        guard let failure else { return relaunch() }
        activate()
        let alert = NSAlert()
        alert.messageText = "The update couldn't be installed"
        alert.informativeText = "\(failure.localizedDescription)\n\nThe current version was not changed."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Release Page")
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(release.pageURL) }
    }

    /// Starts a helper that waits for this process to exit and then opens the new app, and quits.
    private func relaunch() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                            "sh", String(getpid()), Bundle.main.bundleURL.path]
        do { try helper.run() } catch {
            return tell("LangCycle was updated", "Please open it again to use the new version.")
        }
        NSApp.terminate(nil)
    }

    // MARK: Dialogs

    private func tell(_ title: String, _ text: String) {
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}
