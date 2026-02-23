import SwiftUI
import SwiftData

struct DictionaryTab: View {
    @ObservedObject private var dictionary = PersonalDictionary.shared

    @State private var newSpoken = ""
    @State private var newCorrected = ""
    @State private var newAppScope: String = "Global"
    @State private var showAddForm = false
    @State private var selectedFilter: String = "All"
    @State private var cachedKnownApps: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Personal Dictionary")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("Words YapYap has learned from your corrections.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 16)

            // Filter bar
            if !dictionary.appsWithEntries.isEmpty {
                filterBar
                    .padding(.bottom, 12)
            }

            // Entry list
            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }

            Spacer().frame(height: 16)

            // Add correction button / form
            if showAddForm {
                addForm
            } else {
                Button(action: { showAddForm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                        Text("Add Correction")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.ypLavender)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { loadKnownApps() }
    }

    private var filteredEntries: [CorrectionEntry] {
        switch selectedFilter {
        case "All":
            return dictionary.allEntries
        case "Global":
            return dictionary.globalEntries
        default:
            return dictionary.entriesFor(app: selectedFilter)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "All", isSelected: selectedFilter == "All") {
                    selectedFilter = "All"
                }
                filterChip(label: "Global", isSelected: selectedFilter == "Global") {
                    selectedFilter = "Global"
                }
                ForEach(dictionary.appsWithEntries, id: \.self) { app in
                    filterChip(label: app, isSelected: selectedFilter == app) {
                        selectedFilter = app
                    }
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .ypText2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.ypLavender : Color.ypCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.clear : Color.ypBorderLight, lineWidth: 1)
                )
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No corrections yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ypText2)
            Text("YapYap will learn corrections when you edit transcriptions in the popover, or you can add them manually below.")
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ypBorderLight, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Entry List

    private var entryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredEntries.enumerated()), id: \.element.storageKey) { index, entry in
                entryRow(entry: entry)

                if index < filteredEntries.count - 1 {
                    Divider()
                        .background(Color.ypBorderLight)
                        .padding(.horizontal, 12)
                }
            }
        }
        .background(Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ypBorderLight, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func entryRow(entry: CorrectionEntry) -> some View {
        HStack(spacing: 10) {
            // Spoken → Corrected
            HStack(spacing: 6) {
                Text(entry.spoken)
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
                    .strikethrough(!entry.isEnabled, color: .ypText4)

                Text("\u{2192}")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText4)

                Text(entry.corrected)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(entry.isEnabled ? .ypText1 : .ypText3)
            }

            Spacer()

            // App scope badge
            if let app = entry.appName {
                Text(app)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.ypMint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.ypMint.opacity(0.15))
                    .cornerRadius(3)
            }

            // Source badge
            Text(entry.source == .autoLearned ? "auto" : "manual")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(entry.source == .autoLearned ? .ypWarm : .ypLavender)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.source == .autoLearned ? Color.ypPillWarm : Color.ypPillLavender)
                .cornerRadius(3)

            // Hit count
            if entry.hitCount > 0 {
                Text("used \(entry.hitCount)\u{00D7}")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText4)
            }

            // Toggle
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { newValue in
                    dictionary.toggleCorrection(key: entry.storageKey, enabled: newValue)
                }
            ))
            .toggleStyle(YPToggleStyle())

            // Delete
            Button(action: {
                dictionary.removeCorrection(key: entry.storageKey)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Add Form

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPOKEN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText3)
                        .tracking(0.8)
                    TextField("e.g. anthropick", text: $newSpoken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.ypCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.ypBorderLight, lineWidth: 1)
                        )
                        .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("CORRECTED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText3)
                        .tracking(0.8)
                    TextField("e.g. Anthropic", text: $newCorrected)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.ypCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.ypBorderLight, lineWidth: 1)
                        )
                        .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("SCOPE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText3)
                        .tracking(0.8)
                    Picker("", selection: $newAppScope) {
                        Text("Global").tag("Global")
                        ForEach(cachedKnownApps, id: \.self) { app in
                            Text(app).tag(app)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            HStack(spacing: 6) {
                Button(action: addManualCorrection) {
                    Text("Add")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(canAdd ? Color.ypLavender : Color.ypText4)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)

                Button(action: {
                    showAddForm = false
                    newSpoken = ""
                    newCorrected = ""
                    newAppScope = "Global"
                }) {
                    Text("Cancel")
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ypBorderLight, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private var canAdd: Bool {
        !newSpoken.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newCorrected.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Load known apps asynchronously so settings window renders immediately
    private func loadKnownApps() {
        Task { @MainActor in
            var apps = Set(dictionary.appsWithEntries)
            let container = DataManager.shared.container
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Transcription>()
            descriptor.fetchLimit = 500
            if let transcriptions = try? context.fetch(descriptor) {
                for t in transcriptions {
                    if let app = t.sourceApp { apps.insert(app) }
                }
            }
            cachedKnownApps = apps.sorted()
        }
    }

    private func addManualCorrection() {
        let spoken = newSpoken.trimmingCharacters(in: .whitespaces)
        let corrected = newCorrected.trimmingCharacters(in: .whitespaces)
        guard !spoken.isEmpty, !corrected.isEmpty else { return }

        let appName: String? = newAppScope == "Global" ? nil : newAppScope
        dictionary.learnCorrection(spoken: spoken, corrected: corrected, source: .manual, appName: appName)
        newSpoken = ""
        newCorrected = ""
        newAppScope = "Global"
        showAddForm = false
    }
}
