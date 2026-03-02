import SwiftUI
import SwiftData
import MLXLLM
import MLXLMCommon
import Hub

struct ModelsTab: View {
    let appState: AppState?
    @State private var selectedSTT = "whisper-small"
    @State private var selectedLLM = "gemma-3-4b"
    @State private var autoDownload = true
    @State private var gpuAcceleration = true
    @State private var downloadedModels: Set<String> = []
    @State private var downloadingModel: String?
    @State private var downloadProgress: Double = 0
    @State private var modelToDelete: String?
    @State private var showDeleteConfirm = false
    @State private var modelSizes: [String: String] = [:]
    @State private var didLoadSettings = false
    @State private var isRefreshingSettings = false
    @State private var downloadError: String?
    @State private var inferenceFramework: LLMInferenceFramework = .mlx
    @State private var ollamaEndpoint = OllamaEngine.defaultEndpoint
    @State private var ollamaModelName = "qwen2.5:1.5b"
    @State private var ollamaStatus: OllamaConnectionStatus = .unknown
    @State private var selectedGGUF = GGUFModelRegistry.recommendedModel.id

    // All models live under ~/Library/Application Support/YapYap/models/.
    // Application Support is never iCloud-synced, preventing eviction of large
    // mlmodelc/model-weight blobs that cause stat() to hang indefinitely.
    private static var appSupportModelsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YapYap/models")
    }

    private var llmCacheDir: URL {
        Self.appSupportModelsDir.appendingPathComponent("llm")
    }

    private var whisperCacheDir: URL {
        Self.appSupportModelsDir.appendingPathComponent("whisperkit")
    }

    var body: some View {
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

                // LLM Section — framework picker first, then models
                Text("Cleanup & Rewrite Model")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ypText1)
                    .padding(.bottom, 4)
                Text("Choose which LLM cleans up your transcription.")
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
                    .padding(.bottom, 12)

                // Inference framework picker (always visible)
                inferenceFrameworkPicker
                    .padding(.bottom, 16)

                // Framework-specific model selection
                switch inferenceFramework {
                case .mlx:
                    mlxModelSection
                case .llamacpp:
                    ggufModelSection
                case .ollama:
                    ollamaConfigSection
                }

                divider

                // Toggles
                toggleRow(label: "Auto-download models", subtitle: "Download selected models on first use", isOn: $autoDownload)
                toggleRow(label: "GPU acceleration", subtitle: "Use Metal for faster inference", isOn: $gpuAcceleration)

                divider

                // Storage info
            storageInfoSection
        }
        .onAppear {
            loadSettings()
            checkDownloadedModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: .yapSettingsChanged)) { _ in
            isRefreshingSettings = true
            loadSettings()
            isRefreshingSettings = false
            checkDownloadedModels()
        }
        .onChange(of: autoDownload) { _, newValue in
            guard didLoadSettings, !isRefreshingSettings else { return }
            saveSettings { $0.autoDownloadModels = newValue }
        }
        .onChange(of: gpuAcceleration) { _, newValue in
            guard didLoadSettings, !isRefreshingSettings else { return }
            saveSettings { $0.gpuAcceleration = newValue }
        }
        .onChange(of: inferenceFramework) { _, newValue in
            guard didLoadSettings, !isRefreshingSettings else { return }
            saveSettings { $0.llmInferenceFramework = newValue.rawValue }
            NotificationCenter.default.post(name: .yapSettingsChanged, object: nil)
            if newValue == .ollama { checkOllamaConnection() }
        }
        .onChange(of: ollamaEndpoint) { _, newValue in
            guard didLoadSettings, !isRefreshingSettings else { return }
            saveSettings { $0.ollamaEndpoint = newValue }
        }
        .onChange(of: ollamaModelName) { _, newValue in
            guard didLoadSettings, !isRefreshingSettings else { return }
            saveSettings { $0.ollamaModelName = newValue }
        }
        .onChange(of: selectedGGUF) { _, newValue in
            guard didLoadSettings, !isRefreshingSettings else { return }
            saveSettings { $0.llamacppModelId = newValue }
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
                    ?? GGUFModelRegistry.model(for: id)?.name
                    ?? STTModelRegistry.model(for: id)?.name
                    ?? id
                Text("Delete \(name)? This will free up disk space. The model can be re-downloaded later.")
            }
        }
        .alert("Download Failed", isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK", role: .cancel) { downloadError = nil }
        } message: {
            if let error = downloadError {
                Text(error)
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

            Text(modelSizes[model.id] ?? model.sizeDescription)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.ypText4)

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
                    } else if isDownloaded {
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
                    } else {
                        // STT models auto-download on first use via WhisperKit
                        Button(action: { selectSTTModel(model.id) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9))
                                Text("Select & Download")
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
                let isLoaded = appState?.activeLLMModelId == model.id
                let isDownloaded = downloadedModels.contains(model.id)
                // Show downloading state from either manual download OR startup/hotkey load
                let isDownloadingManual = downloadingModel == model.id
                let isDownloadingStartup = appState?.llmLoadingModelId == model.id
                let isDownloading = isDownloadingManual || isDownloadingStartup

                llmModelCard(model: model, isSelected: isSelected, isLoaded: isLoaded, isDownloaded: isDownloaded, isDownloading: isDownloading)
            }
        }
    }

    private func llmModelCard(model: LLMModelInfo, isSelected: Bool, isLoaded: Bool, isDownloaded: Bool, isDownloading: Bool) -> some View {
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

            Text(modelSizes[model.id] ?? model.sizeDescription)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.ypText4)

            Spacer().frame(height: 4)

            // Download progress bar
            if isDownloading {
                let effectiveProgress: Double = {
                    if downloadingModel == model.id {
                        return downloadProgress
                    } else if let p = appState?.llmDownloadProgress {
                        return p
                    }
                    return 0
                }()
                VStack(spacing: 2) {
                    ProgressView(value: effectiveProgress)
                        .progressViewStyle(.linear)
                        .tint(.ypLavender)
                    Text("\(Int(effectiveProgress * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
            } else {
                // Action buttons
                HStack(spacing: 6) {
                    if isLoaded {
                        // Currently loaded in memory — this is what's active right now
                        Text("Loaded")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.ypLavender)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.ypPillLavender)
                            .cornerRadius(4)
                    } else if isSelected {
                        if isDownloaded {
                            // Selected for next use, downloaded, but not yet loaded in memory
                            Text("Selected")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.ypText2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.ypCard2)
                                .cornerRadius(4)
                        } else {
                            // Selected but not downloaded — prompt download
                            Button(action: { downloadAndSelectLLMModel(model) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 9))
                                    Text("Download to Activate")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if isDownloaded {
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
                    } else {
                        // Not downloaded, not selected — download first
                        Button(action: { downloadAndSelectLLMModel(model) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9))
                                Text("Download & Select")
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

    // MARK: - Status Badge

    private func statusBadge(modelId: String, isDownloaded: Bool, isComingSoon: Bool) -> some View {
        // A model is "downloading" if either a manual download is in progress from this tab,
        // or if the startup/hotkey pipeline is loading it (appState.llmLoadingModelId).
        let isDownloadingNow = downloadingModel == modelId || appState?.llmLoadingModelId == modelId
        return Group {
            if isComingSoon {
                Text("Coming soon")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            } else if isDownloadingNow {
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

    // MARK: - Inference Framework Picker

    private var inferenceFrameworkPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            let profile = MachineProfile.current
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
                Text("System: \(profile.tierDescription), \(profile.cpuCoreCount) cores")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
            }

            HStack(spacing: 8) {
                ForEach(LLMInferenceFramework.allCases, id: \.rawValue) { framework in
                    frameworkPill(framework: framework)
                }
            }
        }
    }

    private func frameworkPill(framework: LLMInferenceFramework) -> some View {
        let isSelected = inferenceFramework == framework
        return HStack(spacing: 4) {
            Image(systemName: framework.iconName)
                .font(.system(size: 10))
            Text(framework.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
        }
        .foregroundColor(isSelected ? .ypLavender : .ypText3)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.ypPillLavender : Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.ypLavender : Color.ypBorder, lineWidth: 1)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { inferenceFramework = framework }
    }

    // MARK: - MLX Model Section

    private var mlxModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
                Text("MLX models — Apple GPU optimized, safetensors format")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
            }
            llmModelGrid
        }
    }

    // MARK: - GGUF Model Section

    private var ggufModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
                Text("GGUF models — llama.cpp embedded, no external software needed")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
            }
            ggufModelGrid
        }
    }

    private var ggufModelGrid: some View {
        let models = GGUFModelRegistry.allModels
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(models, id: \.id) { model in
                let isSelected = selectedGGUF == model.id
                let isDownloaded = downloadedModels.contains(model.id)
                let isDownloading = downloadingModel == model.id

                ggufModelCard(model: model, isSelected: isSelected, isDownloaded: isDownloaded, isDownloading: isDownloading)
            }
        }
    }

    private func ggufModelCard(model: GGUFModelInfo, isSelected: Bool, isDownloaded: Bool, isDownloading: Bool) -> some View {
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
                Text("GGUF Q4_K_M")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.ypText4)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.ypText4.opacity(0.1))
                    .cornerRadius(3)
                Text(modelSizes[model.id] ?? model.sizeDescription)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ypText4)
            }

            Spacer().frame(height: 4)

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
                HStack(spacing: 6) {
                    if isSelected && isDownloaded {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.ypLavender)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.ypPillLavender)
                            .cornerRadius(4)
                    } else if isSelected && !isDownloaded {
                        Button(action: { downloadAndSelectGGUFModel(model) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9))
                                Text("Download to Activate")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    } else if isDownloaded {
                        Button(action: { selectGGUFModel(model.id) }) {
                            Text("Select")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.ypText2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.ypCard2)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { downloadAndSelectGGUFModel(model) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9))
                                Text("Download & Select")
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

    // MARK: - Ollama Config Section

    private var ollamaConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(ollamaStatus.color)
                    .frame(width: 8, height: 8)
                Text(ollamaStatus.label)
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
                Spacer()
                Button(action: { checkOllamaConnection() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        Text("Test Connection")
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

            // Server endpoint
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollama Server URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.ypText2)
                TextField("http://localhost:11434", text: $ollamaEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { checkOllamaConnection() }
            }

            // Model name
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.ypText2)
                TextField("qwen2.5:1.5b", text: $ollamaModelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text("Use the exact tag from `ollama list`. The model will be pulled automatically if not present.")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText4)
            }
        }
        .padding(12)
        .background(Color.ypCard)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.ypBorder, lineWidth: 1)
        )
        .padding(.top, 8)
    }

    private func checkOllamaConnection() {
        ollamaStatus = .checking
        Task {
            let url = URL(string: "\(ollamaEndpoint)/api/tags")!
            let request = URLRequest(url: url)
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    await MainActor.run { ollamaStatus = .connected }
                } else {
                    await MainActor.run { ollamaStatus = .error("Unexpected response") }
                }
            } catch {
                await MainActor.run { ollamaStatus = .error(error.localizedDescription) }
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
                label: "MLX models",
                path: llmCacheDir.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                    with: "~"
                )
            )

            storagePathRow(
                label: "GGUF models",
                path: GGUFModelRegistry.ggufModelsDir.path.replacingOccurrences(
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
        NotificationCenter.default.post(name: .yapSettingsChanged, object: nil)
    }

    private func selectLLMModel(_ id: String) {
        selectedLLM = id
        saveSettings { $0.llmModelId = id }
        NotificationCenter.default.post(name: .yapModelSelected, object: nil)
    }

    private func selectGGUFModel(_ id: String) {
        selectedGGUF = id
        saveSettings { $0.llamacppModelId = id }
        NotificationCenter.default.post(name: .yapModelSelected, object: nil)
    }

    private func downloadAndSelectGGUFModel(_ model: GGUFModelInfo) {
        guard downloadingModel == nil else { return }
        downloadingModel = model.id
        downloadProgress = 0

        Task {
            do {
                let ggufDir = GGUFModelRegistry.ggufModelsDir
                try? FileManager.default.createDirectory(at: ggufDir, withIntermediateDirectories: true)

                let destination = GGUFModelRegistry.localPath(for: model)
                let (tempURL, response) = try await URLSession.shared.download(from: model.downloadURL)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw LlamaCppError.downloadFailed(model.downloadURL.absoluteString)
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)

                await MainActor.run {
                    downloadedModels.insert(model.id)
                    downloadingModel = nil
                    downloadProgress = 0
                    selectGGUFModel(model.id)
                }

                // Compute file size
                let modelId = model.id
                let destPath = destination
                DispatchQueue.global(qos: .utility).async {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: destPath.path),
                       let size = attrs[.size] as? Int64 {
                        let formatted = Self.formatBytes(size)
                        DispatchQueue.main.async {
                            self.modelSizes[modelId] = formatted
                        }
                    }
                }
            } catch {
                NSLog("[ModelsTab] GGUF download failed for \(model.id): \(error)")
                await MainActor.run {
                    downloadingModel = nil
                    downloadProgress = 0
                    downloadError = "Failed to download \(model.name): \(error.localizedDescription)"
                }
            }
        }
    }

    private func downloadAndSelectLLMModel(_ model: LLMModelInfo) {
        downloadLLMModel(model, selectAfterDownload: true)
    }

    private func downloadLLMModel(_ model: LLMModelInfo, selectAfterDownload: Bool = false) {
        guard downloadingModel == nil else { return }
        downloadingModel = model.id
        downloadProgress = 0

        Task {
            do {
                let config = ModelConfiguration(id: model.huggingFaceId)
                let factory = LLMModelFactory.shared
                let hub = HubApi(downloadBase: llmCacheDir)

                _ = try await factory.load(
                    hub: hub,
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
                    if selectAfterDownload {
                        selectLLMModel(model.id)
                    }
                }

                // Compute size of the newly downloaded model off-main
                // HubApi stores at {llmCacheDir}/models/{huggingFaceId}
                let hfId = model.huggingFaceId
                let modelId = model.id
                let cache = llmCacheDir
                DispatchQueue.global(qos: .utility).async {
                    let modelDir = cache.appendingPathComponent("models/\(hfId)")
                    if let size = Self.directorySize(at: modelDir) {
                        let formatted = Self.formatBytes(size)
                        DispatchQueue.main.async {
                            self.modelSizes[modelId] = formatted
                        }
                    }
                }
            } catch {
                NSLog("[ModelsTab] Download failed for \(model.id): \(error)")
                await MainActor.run {
                    downloadingModel = nil
                    downloadProgress = 0
                    downloadError = "Failed to download \(model.name): \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteModel(_ id: String) {
        let llmCache = llmCacheDir
        let whisperCache = whisperCacheDir
        Task.detached(priority: .utility) {
            // Try GGUF model deletion
            if let ggufModel = GGUFModelRegistry.model(for: id) {
                let ggufPath = GGUFModelRegistry.localPath(for: ggufModel)
                if FileManager.default.fileExists(atPath: ggufPath.path) {
                    do {
                        try FileManager.default.removeItem(at: ggufPath)
                        NSLog("[ModelsTab] Deleted GGUF model: \(id) at \(ggufPath.path)")
                    } catch {
                        NSLog("[ModelsTab] Failed to delete GGUF model \(id): \(error)")
                    }
                }
            }

            // Try LLM model deletion — HubApi stores at {llmCache}/models/{huggingFaceId}
            if let llmModel = LLMModelRegistry.model(for: id) {
                let modelDir = llmCache.appendingPathComponent("models/\(llmModel.huggingFaceId)")
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
                if FileManager.default.fileExists(atPath: whisperCache.path),
                   let contents = try? FileManager.default.contentsOfDirectory(atPath: whisperCache.path) {
                    for name in contents where name.lowercased().contains(whisperName.lowercased()) || name.lowercased().contains(id.lowercased()) {
                        let fullPath = whisperCache.appendingPathComponent(name)
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
                self.downloadedModels.remove(id)
                self.modelSizes.removeValue(forKey: id)
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
        inferenceFramework = LLMInferenceFramework(rawValue: settings.llmInferenceFramework) ?? .mlx
        ollamaEndpoint = settings.ollamaEndpoint
        ollamaModelName = settings.ollamaModelName
        selectedGGUF = settings.llamacppModelId
        didLoadSettings = true
        if inferenceFramework == .ollama { checkOllamaConnection() }
    }

    private func saveSettings(_ update: (AppSettings) -> Void) {
        DataManager.shared.updateSettings(update)
    }

    // MARK: - Download Detection

    private func checkDownloadedModels() {
        // All file I/O runs on a background dispatch queue to guarantee
        // it never touches the main thread (Task.detached can still
        // resume on main under Swift concurrency).
        DispatchQueue.global(qos: .utility).async {
            var downloaded: Set<String> = []
            var sizes: [String: String] = [:]
            let homeDir = FileManager.default.homeDirectoryForCurrentUser

            // Check LLM models — primary: ~/Library/Application Support/YapYap/models/llm/
            // Legacy fallbacks: ~/Documents/huggingface/models/ (Swift HubApi old default)
            //                   ~/.cache/huggingface/hub/ (Python huggingface_hub)
            let newLLMDir = Self.appSupportModelsDir.appendingPathComponent("llm")
            let legacySwiftDir = homeDir.appendingPathComponent("Documents/huggingface/models")
            let legacyPythonDir = homeDir.appendingPathComponent(".cache/huggingface/hub")
            for model in LLMModelRegistry.allModels {
                // New App Support path — HubApi stores at {downloadBase}/models/{huggingFaceId}
                let newModelDir = newLLMDir.appendingPathComponent("models/\(model.huggingFaceId)")
                if FileManager.default.fileExists(atPath: newModelDir.path) {
                    downloaded.insert(model.id)
                    if let size = Self.directorySize(at: newModelDir) { sizes[model.id] = Self.formatBytes(size) }
                    continue
                }
                // Legacy Swift HubApi path: ~/Documents/huggingface/models/{org}/{modelName}
                let legacySwiftModelDir = legacySwiftDir.appendingPathComponent(model.huggingFaceId)
                if FileManager.default.fileExists(atPath: legacySwiftModelDir.path) {
                    downloaded.insert(model.id)
                    if let size = Self.directorySize(at: legacySwiftModelDir) { sizes[model.id] = Self.formatBytes(size) }
                    continue
                }
                // Legacy Python cache path: ~/.cache/huggingface/hub/models--{org}--{modelName}/snapshots/
                let repoName = "models--" + model.huggingFaceId.replacingOccurrences(of: "/", with: "--")
                let legacyPythonModelDir = legacyPythonDir.appendingPathComponent(repoName)
                if FileManager.default.fileExists(atPath: legacyPythonModelDir.path) {
                    let snapshotsDir = legacyPythonModelDir.appendingPathComponent("snapshots")
                    if let snapshots = try? FileManager.default.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil),
                       !snapshots.isEmpty {
                        downloaded.insert(model.id)
                        if let size = Self.directorySize(at: legacyPythonModelDir) { sizes[model.id] = Self.formatBytes(size) }
                    }
                }
            }

            // Check GGUF models — ~/Library/Application Support/YapYap/models/gguf/
            let ggufDir = GGUFModelRegistry.ggufModelsDir
            for model in GGUFModelRegistry.allModels {
                let ggufPath = GGUFModelRegistry.localPath(for: model)
                if FileManager.default.fileExists(atPath: ggufPath.path) {
                    downloaded.insert(model.id)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: ggufPath.path),
                       let size = attrs[.size] as? Int64 {
                        sizes[model.id] = Self.formatBytes(size)
                    }
                }
            }

            // Check WhisperKit models — prefer new Application Support location, fall back to legacy Documents.
            let whisperDir = whisperCacheDir
            if FileManager.default.fileExists(atPath: whisperDir.path) {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: whisperDir.path) {
                    var smallSize: String? = nil
                    var mediumSize: String? = nil
                    var largeSize: String? = nil

                    for name in contents {
                        let lower = name.lowercased()
                        guard lower.hasPrefix("openai_whisper-") || lower.hasPrefix("distil-whisper") else { continue }
                        let fullPath = whisperDir.appendingPathComponent(name)
                        guard var dirSize = Self.directorySize(at: fullPath), dirSize > 0 else { continue }
                        let formatted = Self.formatBytes(dirSize)

                        // "openai_whisper-small..." but NOT "openai_whisper-small.en"
                        // Match: openai_whisper-small, openai_whisper-small_216MB
                        if lower.hasPrefix("openai_whisper-small") && !lower.contains(".en") {
                            if smallSize == nil { smallSize = formatted }
                        }
                        // "openai_whisper-medium..." but NOT medium.en
                        else if lower.hasPrefix("openai_whisper-medium") && !lower.contains(".en") {
                            if mediumSize == nil { mediumSize = formatted }
                        }
                        // Large-v3 turbo variants: openai_whisper-large-v3*turbo* or distil-whisper*turbo*
                        else if (lower.hasPrefix("openai_whisper-large-v3") || lower.hasPrefix("distil-whisper")) && lower.contains("turbo") {
                            if largeSize == nil { largeSize = formatted }
                        }
                    }

                    if let s = smallSize { downloaded.insert("whisper-small"); sizes["whisper-small"] = s }
                    if let m = mediumSize { downloaded.insert("whisper-medium"); sizes["whisper-medium"] = m }
                    if let l = largeSize { downloaded.insert("whisper-large-v3-turbo"); sizes["whisper-large-v3-turbo"] = l }
                }
            }

            // SpeechAnalyzer is always available on macOS 26+ (system framework)
            if #available(macOS 26, *) {
                downloaded.insert("apple-speech-analyzer")
            }

            // Also include models marked as downloaded in the database.
            // MLXEngine calls DataManager.markModelDownloaded() after successful load,
            // which covers models whose cache layout doesn't match the filesystem checks above.
            let markedIds = DataManager.shared.downloadedModelIds()
            downloaded.formUnion(markedIds)

            DispatchQueue.main.async { [downloaded, sizes] in
                self.downloadedModels = downloaded
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

// MARK: - Ollama Connection Status

enum OllamaConnectionStatus {
    case unknown
    case checking
    case connected
    case error(String)

    var label: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .checking: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}
