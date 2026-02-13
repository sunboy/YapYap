import SwiftUI

struct ModelCardInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let size: String
}

struct ModelsTab: View {
    @State private var selectedSTT = "whisper-large-v3"
    @State private var selectedLLM = "qwen-2.5-3b"
    @State private var autoDownload = true
    @State private var gpuAcceleration = true

    private let sttModels: [ModelCardInfo] = [
        ModelCardInfo(id: "whisper-large-v3", name: "Whisper Large v3", description: "Best accuracy across accents and languages.", size: "~1.5 GB · Apple Silicon optimized"),
        ModelCardInfo(id: "whisper-medium", name: "Whisper Medium", description: "Good balance of speed and accuracy.", size: "~769 MB · Faster inference"),
        ModelCardInfo(id: "whisper-small", name: "Whisper Small", description: "Lightweight, best for older hardware.", size: "~244 MB · Low resource"),
        ModelCardInfo(id: "parakeet-tdt-v3", name: "Parakeet TDT v3", description: "NVIDIA's SOTA. Runs on Neural Engine.", size: "~600 MB · Recommended"),
        ModelCardInfo(id: "voqstral", name: "Voqstral", description: "Mistral's STT. Ultra-low latency.", size: "~650 MB · Experimental"),
    ]

    private let llmModels: [ModelCardInfo] = [
        ModelCardInfo(id: "qwen-2.5-3b", name: "Qwen 2.5 3B", description: "Fast, efficient, great multilingual.", size: "~2.0 GB · Recommended"),
        ModelCardInfo(id: "qwen-2.5-7b", name: "Qwen 2.5 7B", description: "More nuanced rewrites. 16GB+ RAM.", size: "~4.7 GB · Higher quality"),
        ModelCardInfo(id: "llama-3.2-3b", name: "Llama 3.2 3B", description: "Great at tone-matching and style.", size: "~2.0 GB · Good all-rounder"),
        ModelCardInfo(id: "llama-3.1-8b", name: "Llama 3.1 8B", description: "Best rewrite quality. 16GB+ RAM.", size: "~4.7 GB · Power users"),
    ]

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

            modelGrid(models: sttModels, selected: $selectedSTT)

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

            modelGrid(models: llmModels, selected: $selectedLLM)

            divider

            // Toggles
            toggleRow(label: "Auto-download models", subtitle: "Download selected models on first use", isOn: $autoDownload)
            toggleRow(label: "GPU acceleration", subtitle: "Use Metal for faster inference", isOn: $gpuAcceleration)
        }
    }

    private func modelGrid(models: [ModelCardInfo], selected: Binding<String>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(models) { model in
                modelCard(model: model, isSelected: selected.wrappedValue == model.id)
                    .onTapGesture { selected.wrappedValue = model.id }
            }
        }
    }

    private func modelCard(model: ModelCardInfo, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ypText1)
            Text(model.description)
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .lineSpacing(2)
            Spacer().frame(height: 6)
            Text(model.size)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.ypText4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.ypPillLavender : Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.ypLavender : Color.ypBorder, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Text("✓")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.ypLavender)
                    .padding(10)
            }
        }
        .cornerRadius(10)
    }

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
