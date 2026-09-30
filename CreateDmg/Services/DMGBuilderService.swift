import Foundation

enum DMGBuilderError: LocalizedError {
    case appBundleMissing(String)
    case invalidAppBundle(String)
    case additionalItemMissing(String)
    case outputDirectoryMissing(String)
    case outputAlreadyExists(String)
    case duplicateItemName(String)
    case hdiutilMissing
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .appBundleMissing(let path):
            return "App does not exist: \(path)"
        case .invalidAppBundle(let path):
            return "Please select a valid .app bundle: \(path)"
        case .additionalItemMissing(let path):
            return "Additional file or folder does not exist: \(path)"
        case .outputDirectoryMissing(let path):
            return "Output directory does not exist: \(path)"
        case .outputAlreadyExists(let path):
            return "A DMG already exists at this path: \(path)"
        case .duplicateItemName(let name):
            return "Two selected items would have the same name in the DMG: \(name)"
        case .hdiutilMissing:
            return "macOS hdiutil was not found at /usr/bin/hdiutil."
        case .processLaunchFailed(let message):
            return "Failed to start hdiutil: \(message)"
        }
    }
}

struct DMGBuildRequest: Sendable {
    let appBundlePath: String
    let additionalFilePaths: [String]
    let outputDirectory: String
    let overwrite: Bool
    let includeVersionInFilename: Bool
    let dmgTitle: String
}

final class DMGBuilderService {
    typealias LogHandler = @Sendable (String) -> Void

    func build(request: DMGBuildRequest, onOutput: @escaping LogHandler) async throws -> DMGBuildResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: request.appBundlePath, isDirectory: &isDirectory) else {
            throw DMGBuilderError.appBundleMissing(request.appBundlePath)
        }
        guard isDirectory.boolValue, request.appBundlePath.lowercased().hasSuffix(".app") else {
            throw DMGBuilderError.invalidAppBundle(request.appBundlePath)
        }
        let outputDirectoryURL = URL(fileURLWithPath: request.outputDirectory, isDirectory: true)
        guard fileManager.fileExists(atPath: outputDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DMGBuilderError.outputDirectoryMissing(request.outputDirectory)
        }
        let hdiutilURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        guard fileManager.isExecutableFile(atPath: hdiutilURL.path) else {
            throw DMGBuilderError.hdiutilMissing
        }

        let appURL = URL(fileURLWithPath: request.appBundlePath, isDirectory: true)
        let appName = appURL.deletingPathExtension().lastPathComponent
        let appVersion = Bundle(path: appURL.path)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let dmgFilename = Self.dmgFilename(
            appName: appName,
            version: appVersion,
            includeVersion: request.includeVersionInFilename
        )
        let outputURL = outputDirectoryURL.appendingPathComponent(dmgFilename)
        if fileManager.fileExists(atPath: outputURL.path), !request.overwrite {
            throw DMGBuilderError.outputAlreadyExists(outputURL.path)
        }

        let additionalURLs = request.additionalFilePaths.map { URL(fileURLWithPath: $0) }
        for url in additionalURLs where !fileManager.fileExists(atPath: url.path) {
            throw DMGBuilderError.additionalItemMissing(url.path)
        }
        try Self.validateNames(appURL: appURL, additionalURLs: additionalURLs)

        let stagingURL = fileManager.temporaryDirectory
            .appendingPathComponent("DMGBuilder-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        do {
            onOutput("Preparing DMG contents…\n")
            try fileManager.copyItem(at: appURL, to: stagingURL.appendingPathComponent(appURL.lastPathComponent))
            for url in additionalURLs {
                onOutput("Adding \(url.lastPathComponent)…\n")
                try fileManager.copyItem(at: url, to: stagingURL.appendingPathComponent(url.lastPathComponent))
            }
            try fileManager.createSymbolicLink(
                at: stagingURL.appendingPathComponent("Applications"),
                withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }

        let volumeTitle = request.dmgTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appName
            : request.dmgTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let logCollector = LogCollector(onOutput: onOutput)

            var arguments = [
                "create",
                "-volname", volumeTitle,
                "-srcfolder", stagingURL.path,
                "-format", "UDZO"
            ]
            if request.overwrite { arguments.append("-ov") }
            arguments.append(outputURL.path)

            process.executableURL = hdiutilURL
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            stdout.fileHandleForReading.readabilityHandler = { logCollector.append($0.availableData) }
            stderr.fileHandleForReading.readabilityHandler = { logCollector.append($0.availableData) }

            process.terminationHandler = { finishedProcess in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                logCollector.append(stdout.fileHandleForReading.readDataToEndOfFile())
                logCollector.append(stderr.fileHandleForReading.readDataToEndOfFile())
                try? FileManager.default.removeItem(at: stagingURL)
                let outputExists = FileManager.default.fileExists(atPath: outputURL.path)
                continuation.resume(returning: DMGBuildResult(
                    success: finishedProcess.terminationStatus == 0 && outputExists,
                    exitCode: finishedProcess.terminationStatus,
                    log: logCollector.log,
                    outputURL: outputExists ? outputURL : nil
                ))
            }

            do {
                try process.run()
                onOutput("Creating disk image…\n")
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                try? fileManager.removeItem(at: stagingURL)
                continuation.resume(throwing: DMGBuilderError.processLaunchFailed(error.localizedDescription))
            }
        }
    }

    private nonisolated static func dmgFilename(appName: String, version: String?, includeVersion: Bool) -> String {
        let safeName = appName.replacingOccurrences(of: "/", with: "-")
        if includeVersion, let version, !version.isEmpty {
            return "\(safeName) \(version).dmg"
        }
        return "\(safeName).dmg"
    }

    private nonisolated static func validateNames(appURL: URL, additionalURLs: [URL]) throws {
        var names: Set<String> = [appURL.lastPathComponent.lowercased(), "applications"]
        for url in additionalURLs {
            let name = url.lastPathComponent.lowercased()
            guard names.insert(name).inserted else {
                throw DMGBuilderError.duplicateItemName(url.lastPathComponent)
            }
        }
    }
}

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var contents = ""
    private let onOutput: DMGBuilderService.LogHandler

    init(onOutput: @escaping DMGBuilderService.LogHandler) {
        self.onOutput = onOutput
    }

    var log: String {
        lock.lock()
        defer { lock.unlock() }
        return contents
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        contents += text
        lock.unlock()
        onOutput(text)
    }
}
