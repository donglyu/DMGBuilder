import AppKit
import Combine
import Foundation

@MainActor
final class DMGBuilderViewModel: ObservableObject {
    @Published var appBundlePath: String { didSet { defaults.set(appBundlePath, forKey: Key.appBundlePath.rawValue) } }
    @Published var additionalFilePaths: [String] { didSet { defaults.set(additionalFilePaths, forKey: Key.additionalFilePaths.rawValue) } }
    @Published var outputDirectory: String { didSet { defaults.set(outputDirectory, forKey: Key.outputDirectory.rawValue) } }
    @Published var overwrite: Bool { didSet { defaults.set(overwrite, forKey: Key.overwrite.rawValue) } }
    @Published var includeVersionInFilename: Bool { didSet { defaults.set(includeVersionInFilename, forKey: Key.includeVersion.rawValue) } }
    @Published var dmgTitle: String { didSet { defaults.set(dmgTitle, forKey: Key.dmgTitle.rawValue) } }

    @Published private(set) var log = ""
    @Published private(set) var isBuilding = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var buildSucceeded = false
    @Published private(set) var outputURL: URL?

    private let defaults: UserDefaults
    private let service: DMGBuilderService

    init(defaults: UserDefaults = .standard, service: DMGBuilderService = DMGBuilderService()) {
        self.defaults = defaults
        self.service = service
        appBundlePath = defaults.string(forKey: Key.appBundlePath.rawValue) ?? ""
        additionalFilePaths = defaults.stringArray(forKey: Key.additionalFilePaths.rawValue) ?? []
        outputDirectory = defaults.string(forKey: Key.outputDirectory.rawValue) ?? ""
        overwrite = defaults.object(forKey: Key.overwrite.rawValue) as? Bool ?? true
        includeVersionInFilename = defaults.object(forKey: Key.includeVersion.rawValue) as? Bool ?? true
        dmgTitle = defaults.string(forKey: Key.dmgTitle.rawValue) ?? ""
    }

    var appName: String {
        guard !appBundlePath.isEmpty else { return "No app selected" }
        return URL(fileURLWithPath: appBundlePath).deletingPathExtension().lastPathComponent
    }

    var appVersion: String? {
        guard !appBundlePath.isEmpty, let bundle = Bundle(path: appBundlePath) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = "Choose the macOS app to package"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appBundlePath = url.path
        if dmgTitle.isEmpty { dmgTitle = url.deletingPathExtension().lastPathComponent }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose where the DMG should be saved"
        if panel.runModal() == .OK, let url = panel.url { outputDirectory = url.path }
    }

    func addAdditionalFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose files or folders to include at the top level of the DMG"
        guard panel.runModal() == .OK else { return }
        let existingPaths = Set(additionalFilePaths)
        let newPaths = panel.urls.map(\.path).filter { !existingPaths.contains($0) }
        additionalFilePaths.append(contentsOf: newPaths)
    }

    func removeAdditionalFile(at index: Int) {
        guard additionalFilePaths.indices.contains(index) else { return }
        additionalFilePaths.remove(at: index)
    }

    func clearLog() { log = "" }

    func build() {
        guard validateFields() else { return }
        isBuilding = true
        buildSucceeded = false
        outputURL = nil
        statusMessage = nil
        log = "Starting DMG build…\n\nApp: \(appBundlePath)\nAdditional items: \(additionalFilePaths.count)\nOutput: \(outputDirectory)\n\n"

        let request = DMGBuildRequest(
            appBundlePath: appBundlePath,
            additionalFilePaths: additionalFilePaths,
            outputDirectory: outputDirectory,
            overwrite: overwrite,
            includeVersionInFilename: includeVersionInFilename,
            dmgTitle: dmgTitle
        )

        Task {
            do {
                let result = try await service.build(request: request) { text in
                    Task { @MainActor in self.log += text }
                }
                isBuilding = false
                outputURL = result.outputURL
                buildSucceeded = result.success
                if result.success {
                    statusMessage = "DMG created successfully"
                    log += "\nDMG created successfully.\n"
                } else {
                    statusMessage = "create-dmg failed with exit code \(result.exitCode)"
                    log += "\ncreate-dmg failed with exit code \(result.exitCode).\n"
                }
            } catch {
                isBuilding = false
                buildSucceeded = false
                statusMessage = error.localizedDescription
                log += "Error: \(error.localizedDescription)\n"
            }
        }
    }

    func showInFinder() {
        if let outputURL {
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } else if !outputDirectory.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: outputDirectory, isDirectory: true))
        }
    }

    private func validateFields() -> Bool {
        if appBundlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reportValidationError("App is required.")
            return false
        }
        if outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reportValidationError("Output Directory is required.")
            return false
        }
        return true
    }

    private func reportValidationError(_ message: String) {
        buildSucceeded = false
        statusMessage = message
        log += "Error: \(message)\n"
    }

    private enum Key: String {
        case appBundlePath
        case additionalFilePaths
        case outputDirectory
        case overwrite
        case includeVersion
        case dmgTitle
    }
}
