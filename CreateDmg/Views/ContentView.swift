import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DMGBuilderViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    sourceCard
                    additionalFilesCard
                    optionsCard
                    buildSection
                    logCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 660, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("DMG Builder").font(.title2.bold())
                Text("Package your app and supporting files into a disk image")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var sourceCard: some View {
        card(title: "Build Source", icon: "app.dashed") {
            VStack(spacing: 14) {
                pathRow(
                    title: "Application",
                    placeholder: "Choose a compiled .app bundle",
                    text: $viewModel.appBundlePath,
                    action: viewModel.chooseApp
                )
                Divider()
                pathRow(
                    title: "Destination",
                    placeholder: "Choose an output directory",
                    text: $viewModel.outputDirectory,
                    action: viewModel.chooseOutputDirectory
                )
            }
        }
    }

    private var optionsCard: some View {
        card(title: "DMG Options", icon: "slider.horizontal.3") {
            VStack(spacing: 14) {
                HStack {
                    Text("Disk name").frame(width: 118, alignment: .leading)
                    TextField(viewModel.appName, text: $viewModel.dmgTitle)
                }
                Divider()
                HStack(spacing: 22) {
                    Toggle("Overwrite existing DMG", isOn: $viewModel.overwrite)
                    Toggle("Include version in filename", isOn: $viewModel.includeVersionInFilename)
                    Spacer(minLength: 0)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var additionalFilesCard: some View {
        card(title: "Additional Files", icon: "doc.on.doc") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected files and folders will appear beside the app in the DMG.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.additionalFilePaths.isEmpty {
                    Text("No additional items selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.additionalFilePaths.enumerated()), id: \.element) { index, path in
                            HStack(spacing: 10) {
                                Image(systemName: path.lowercased().hasSuffix(".app") ? "app.dashed" : "doc.text")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .lineLimit(1)
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    viewModel.removeAdditionalFile(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove item")
                            }
                            .padding(.vertical, 7)
                            if index < viewModel.additionalFilePaths.count - 1 { Divider() }
                        }
                    }
                }

                Button("Add Files…", systemImage: "plus", action: viewModel.addAdditionalFiles)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var buildSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.appName).font(.headline)
                    if let version = viewModel.appVersion {
                        Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.isBuilding { ProgressView().controlSize(.small) }
                Button(viewModel.isBuilding ? "Creating DMG…" : "Create DMG") {
                    viewModel.build()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isBuilding)
            }

            if let status = viewModel.statusMessage {
                HStack {
                    Label(status, systemImage: viewModel.buildSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.buildSucceeded ? .green : .red)
                    Spacer()
                    if viewModel.buildSucceeded {
                        Button("Show in Finder", action: viewModel.showInFinder)
                    }
                }
                .padding(10)
                .background((viewModel.buildSucceeded ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var logCard: some View {
        card(title: "Build Log", icon: "terminal") {
            VStack(spacing: 8) {
                HStack {
                    Text("Live output from hdiutil").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", action: viewModel.clearLog)
                        .buttonStyle(.plain)
                        .disabled(viewModel.log.isEmpty)
                }
                ScrollView {
                    Text(viewModel.log.isEmpty ? "Build output will appear here." : viewModel.log)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(viewModel.log.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .frame(minHeight: 150)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
            }
        }
    }

    private func card<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.7)))
    }

    private func pathRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title).frame(width: 118, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
            Button("Choose…", action: action)
        }
    }
}
