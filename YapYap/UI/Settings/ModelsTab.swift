import SwiftUI
import SwiftData
import MLXLLM
import MLXLMCommon
import Hub

struct ModelsTab: View {
    @State private var selectedSTT = "whisper-small"
    @State private var selectedLLM = "qwen-2.5-1.5b"
    @State private var autoDownload = true
    @State private var gpuAcceleration = true
    @State private var downloadedModels: Set<String> = []
    @State private var downloadingModel: String?
    @State private var downloadProgress: Double = 0
    @State private var modelToDelete: String?
    @State private var showDeleteConfirm = false
    @State private var modelSizes: [String: String] = [:]

    private var llmCacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
    }

    private var whisperCacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // STT Section
                Text("Speech-to-Text Model")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ypText1)
                    .padding(.bottom, 4)
                Text("Choose which model transcribes your voice. Runs locally.")
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
                    .padding(.bottom, 20)

                sttModelGrid

                divider

                // LLM Section
                Text("Cleanup & Rewrite Model")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ypText1)
                    .padding(.bottom, 4)
                Text("Choose which LLM cleans up your transcription.")
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
                    .padding(.bottom, 20)

                llmModelGrid

                divider

                // Toggles
                toggleRow(label: "Auto-download models", subtitle: "Download selected models on first use", isOn: $autoDownload)
                toggleRow(label: "GPU acceleration", subtitle: "Use Metal for faster inference", isOn: $gpuAcceleration)

                divider

                // Storage info
                storageInfoSection
            }
        }
        .onAppear {
            loadSettings()
            checkDownloadedModels()
        }
        .onChange(of: autoDownload) { _, newValue in
            saveSettings { $0.autoDownloadModels = newValue }
        }
        .onChange(of: gpuAcceleration) { _, newValue in
            saveSettings { $0.gpuAcceleration = newValue }
        }
        .alert("Delete Model", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = modelToDelete {
                    deleteModel(id)
                    modelToDelete = nil
                }
            }
        } message: {
            if let id = modelToDelete {
                let name = LLMModelRegistry.model(for: id)?.name
                    ?? STTModelRegistry.model(for: id)?.name
                    ?? id
                Text("Delete \(name)? This will free up disk space. The model can be re-downloaded later.")
            }
        }
    }

    // MARK: - STT Model Grid

    private var sttModelGrid: some View {
        let models = STTModelRegistry.allModels
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(models, id: \.id) { model in
                let isComingSoon = model.id == "voxtral-mini-3b"
                let isSelected = selectedSTT == model.id
                let isDownloaded = downloadedModels.contains(model.id)

                sttModelCard(model: model, isSelected: isSelected, isDownloaded: isDownloaded, isComingSoon: isComingSoon)
                    .opacity(isComingSoon ? 0.5 : 1.0)
            }
        }
    }

    private func sttModelCard(model: STTModelInfo, isSelected: Bool, isDownloaded: Bool, isComingSoon: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ypText1)
                Spacer()
                statusBadge(modelId: model.id, isDownloaded: isDownloaded, isComingSoon: isComingSoon)
            }

            Text(model.description)
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .lineSpacing(2)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(model.sizeDescription)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ypText4)
                if isDownloaded, let diskSize = modelSizes[model.id] {
                    Text("(\(diskSize) on disk)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
            }

            Spacer().frame(height: 4)

            // Action buttons
            if !isComingSoon {
                HStack(spacing: 6) {
                    if isSelected {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.ypLavender)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.ypPillLavender)
                            .cornerRadius(4)
                    } else {
                        Button(action: { selectSTTModel(model.id) }) {
                            Text("Select")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.ypText2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.ypCard2)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if isDownloaded && !isSelected {
                        Button(action: {
                            modelToDelete = model.id
                            showDeleteConfirm = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text("Delete")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.ypPillLavender : Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.ypLavender : Color.ypBorder, lineWidth: 1.5)
        )
        .cornerRadius(10)
    }

    // MARK: - LLM Model Grid

    private var llmModelGrid: some View {
        let models = LLMModelRegistry.allModels
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(models, id: \.id) { model in
                let isSelected = selectedLLM == model.id
                let isDownloaded = downloadedModels.contains(model.id)
                let isDownloading = downloadingModel == model.id

                llmModelCard(model: model, isSelected: isSelected, isDownloaded: isDownloaded, isDownloading: isDownloading)
            }
        }
    }

    private func llmModelCard(model: LLMModelInfo, isSelected: Bool, isDownloaded: Bool, isDownloading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ypText1)
                Spacer()
                statusBadge(modelId: model.id, isDownloaded: isDownloaded, isComingSoon: false)
            }

            Text(model.description)
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .lineSpacing(2)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(model.sizeDescription)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ypText4)
                if isDownloaded, let diskSize = modelSizes[model.id] {
                    Text("(\(diskSize) on disk)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
            }

            Spacer().frame(height: 4)

            // Download progress bar
            if isDownloading {
                VStack(spacing: 2) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.ypLavender)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
            } else {
                // Action buttons
                HStack(spacing: 6) {
                    if isSelected {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.ypLavender)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.ypPillLavender)
                            .cornerRadius(4)
                    } else {
                        Button(action: { selectLLMModel(model.id) }) {
                            Text("Select")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.ypText2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.ypCard2)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if isDownloaded && !isSelected {
                        Button(action: {
                            modelToDelete = model.id
                            showDeleteConfirm = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text("Delete")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    if !isDownloaded {
                        Button(action: { downloadLLMModel(model) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9))
                                Text("Download")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.ypLavender)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.ypPillLavender)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.ypPillLavender : Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.ypLavender : Color.ypBorder, lineWidth: 1.5)
        )
        .cornerRadius(10)
    }

    // MARK: - Status Badge

    private func statusBadge(modelId: String, isDownloaded: Bool, isComingSoon: Bool) -> some View {
        Group {
            if isComingSoon {
                Text("Coming soon")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            } else if downloadingModel == modelId {
                Text("Downloading")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.ypLavender)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.ypPillLavender)
                    .cornerRadius(4)
            } else if isDownloaded {
                Text("Downloaded")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.green.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            } else {
                Text("Not downloaded")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.ypText4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.ypText4.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Storage Info

    private var storageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Storage")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)

            storagePathRow(
                label: "LLM models",
                path: llmCacheDir.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                    with: "~"
                )
            )

            storagePathRow(
                label: "WhisperKit models",
                path: whisperCacheDir.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                    with: "~"
                )
            )
        }
    }

    private func storagePathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ypText2)
            HStack(spacing: 6) {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ypText3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(action: {
                    let fullPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fullPath)
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.ypLavender)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func selectSTTModel(_ id: String) {
        selectedSTT = id
        saveSettings { $0.sttModelId = id }
    }

    private func selectLLMModel(_ id: String) {
        selectedLLM = id
        saveSettings { $0.llmModelId = id }
    }

    private func downloadLLMModel(_ model: LLMModelInfo) {
        guard downloadingModel == nil else { return }
        downloadingModel = model.id
        downloadProgress = 0

        Task {
            do {
                let config = ModelConfiguration(id: model.huggingFaceId)
                let factory = LLMModelFactory.shared

                _ = try await factory.load(
                    hub: HubApi(),
                    configuration: config
                ) { progress in
                    Task { @MainActor in
                        downloadProgress = progress.fractionCompleted
                    }
                }

                await MainActor.run {
                    downloadedModels.insert(model.id)
                    downloadingModel = nil
                    downloadProgress = 0
                    computeModelSizes()
                }
            } catch {
                NSLog("[ModelsTab] Download failed for \(model.id): \(error)")
                await MainActor.run {
                    downloadingModel = nil
                    downloadProgress = 0
                }
            }
        }
    }

    private func deleteModel(_ id: String) {
        Task {
            // Try LLM model deletion
            if let llmModel = LLMModelRegistry.model(for: id) {
                let repoName = "models--" + llmModel.huggingFaceId.replacingOccurrences(of: "/", with: "--")
                let modelDir = llmCacheDir.appendingPathComponent(repoName)
                if FileManager.default.fileExists(atPath: modelDir.path) {
                    do {
                        try FileManager.default.removeItem(at: modelDir)
                        NSLog("[ModelsTab] Deleted LLM model: \(id) at \(modelDir.path)")
                    } catch {
                        NSLog("[ModelsTab] Failed to delete LLM model \(id): \(error)")
                    }
                }
            }

            // Try STT (WhisperKit) model deletion
            if let sttModel = STTModelRegistry.model(for: id), sttModel.backend == .whisperKit {
                let whisperName = id.replacingOccurrences(of: "whisper-", with: "openai_whisper-")
                if FileManager.default.fileExists(atPath: whisperCacheDir.path),
                   let contents = try? FileManager.default.contentsOfDirectory(atPath: whisperCacheDir.path) {
                    for name in contents where name.lowercased().contains(whisperName.lowercased()) || name.lowercased().contains(id.lowercased()) {
                        let fullPath = whisperCacheDir.appendingPathComponent(name)
                        do {
                            try FileManager.default.removeItem(at: fullPath)
                            NSLog("[ModelsTab] Deleted STT model: \(id) at \(fullPath.path)")
                        } catch {
                            NSLog("[ModelsTab] Failed to delete STT model \(id): \(error)")
                        }
                    }
                }
            }

            await MainActor.run {
                downloadedModels.remove(id)
                modelSizes.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        let settings = DataManager.shared.fetchSettings()
        selectedSTT = settings.sttModelId
        selectedLLM = settings.llmModelId
        autoDownload = settings.autoDownloadModels
        gpuAcceleration = settings.gpuAcceleration
    }

    private func saveSettings(_ update: (AppSettings) -> Void) {
        let settings = DataManager.shared.fetchSettings()
        update(settings)
        try? DataManager.shared.container.mainContext.save()
    }

    // MARK: - Download Detection

    private func checkDownloadedModels() {
        Task {
            var downloaded: Set<String> = []
            let homeDir = FileManager.default.homeDirectoryForCurrentUser

            // Check LLM models in ~/.cache/huggingface/hub/
            let hfCacheDir = homeDir.appendingPathComponent(".cache/huggingface/hub")
            for model in LLMModelRegistry.allModels {
                let repoName = "models--" + model.huggingFaceId.replacingOccurrences(of: "/", with: "--")
                let modelDir = hfCacheDir.appendingPathComponent(repoName)
                if FileManager.default.fileExists(atPath: modelDir.path) {
                    let snapshotsDir = modelDir.appendingPathComponent("snapshots")
                    if let snapshots = try? FileManager.default.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil),
                       !snapshots.isEmpty {
                        downloaded.insert(model.id)
                    }
                }
            }

            // Check WhisperKit models in ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/
            let whisperDir = homeDir.appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
            if FileManager.default.fileExists(atPath: whisperDir.path) {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: whisperDir.path) {
                    for name in contents {
                        let lower = name.lowercased()
                        if lower.contains("whisper-small") || lower.contains("whisper_small") { downloaded.insert("whisper-small") }
                        if lower.contains("whisper-medium") || lower.contains("whisper_medium") { downloaded.insert("whisper-medium") }
                        if lower.contains("whisper-large") || lower.contains("whisper_large") { downloaded.insert("whisper-large-v3-turbo") }
                    }
                }
            }

            await MainActor.run {
                self.downloadedModels = downloaded
                computeModelSizes()
            }
        }
    }

    private func computeModelSizes() {
        Task {
            var sizes: [String: String] = [:]

            // LLM model sizes
            for model in LLMModelRegistry.allModels where downloadedModels.contains(model.id) {
                let repoName = "models--" + model.huggingFaceId.replacingOccurrences(of: "/", with: "--")
                let modelDir = llmCacheDir.appendingPathComponent(repoName)
                if let size = Self.directorySize(at: modelDir) {
                    sizes[model.id] = Self.formatBytes(size)
                }
            }

            // WhisperKit model sizes
            if FileManager.default.fileExists(atPath: whisperCacheDir.path),
               let contents = try? FileManager.default.contentsOfDirectory(atPath: whisperCacheDir.path) {
                for name in contents {
                    let lower = name.lowercased()
                    let fullPath = whisperCacheDir.appendingPathComponent(name)
                    guard let size = Self.directorySize(at: fullPath) else { continue }
                    let formatted = Self.formatBytes(size)
                    if lower.contains("whisper-small") || lower.contains("whisper_small") { sizes["whisper-small"] = formatted }
                    if lower.contains("whisper-medium") || lower.contains("whisper_medium") { sizes["whisper-medium"] = formatted }
                    if lower.contains("whisper-large") || lower.contains("whisper_large") { sizes["whisper-large-v3-turbo"] = formatted }
                }
            }

            await MainActor.run {
                self.modelSizes = sizes
            }
        }
    }

    private static func directorySize(at url: URL) -> Int64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    // MARK: - UI Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.ypBorderLight)
            .frame(height: 1)
            .padding(.vertical, 24)
    }

    private func toggleRow(label: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.ypText2)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(YPToggleStyle())
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ypBorderLight).frame(height: 1)
        }
    }
}
