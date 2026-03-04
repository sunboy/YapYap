// PromptsTab.swift
// YapYap — Settings tab for customizing system prompts, few-shot examples, and app rules
import SwiftUI

struct PromptsTab: View {
    @State private var overrides = PromptOverrides()
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?

    // Section expand state
    @State private var expandedSystemVariant: PromptOverrides.SystemPromptVariant?
    @State private var fewShotExpanded = false
    @State private var expandedCategory: AppCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Customize the AI prompts used for text cleanup.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 4)

            Text("Each section has built-in defaults you can restore at any time.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            // ── Section 1: System Prompts ──
            systemPromptsSection

            SettingsSectionDivider()

            // ── Section 2: Few-Shot Examples ──
            fewShotExamplesSection

            SettingsSectionDivider()

            // ── Section 3: App-Specific Rules ──
            appSpecificRulesSection
        }
        .onAppear {
            guard !didLoad else { return }
            overrides = PromptOverrides.loadFromUserDefaults()
            didLoad = true
        }
    }

    // MARK: - Debounced Save

    private func debounceSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            overrides.saveToUserDefaults()
        }
    }

    private func saveImmediately() {
        saveTask?.cancel()
        overrides.saveToUserDefaults()
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section 1: System Prompts
    // ═══════════════════════════════════════════════════════════════════

    private var systemPromptsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                label: "SYSTEM PROMPT",
                icon: "gearshape",
                description: "Base instructions sent to the LLM. Formality and style modifiers are appended automatically."
            )

            VStack(spacing: 2) {
                ForEach(PromptOverrides.SystemPromptVariant.allCases) { variant in
                    systemPromptRow(variant)
                }
            }

            // Reset button
            if overrides.systemSmallLight != nil || overrides.systemSmallMedium != nil ||
               overrides.systemSmallHeavy != nil || overrides.systemUnified != nil {
                HStack {
                    Spacer()
                    Button("Reset All System Prompts") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            overrides.systemSmallLight = nil
                            overrides.systemSmallMedium = nil
                            overrides.systemSmallHeavy = nil
                            overrides.systemUnified = nil
                            expandedSystemVariant = nil
                            saveImmediately()
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func systemPromptRow(_ variant: PromptOverrides.SystemPromptVariant) -> some View {
        let isExpanded = expandedSystemVariant == variant
        let override = overrides.systemPromptOverride(for: variant)
        let hasOverride = override != nil
        let isEnabled = override?.isEnabled ?? false

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: variant.icon)
                    .font(.system(size: 12))
                    .foregroundColor(hasOverride && isEnabled ? .ypLavender : .ypText3)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(variant.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ypText1)

                    Text(variant.description)
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                }

                Spacer()

                overrideBadge(hasOverride: hasOverride, isEnabled: isEnabled)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedSystemVariant = isExpanded ? nil : variant
                }
            }

            // Expanded editor
            if isExpanded {
                systemPromptEditor(variant)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isExpanded ? Color.white.opacity(0.04) : Color.clear)
        )
    }

    @ViewBuilder
    private func systemPromptEditor(_ variant: PromptOverrides.SystemPromptVariant) -> some View {
        let override = overrides.systemPromptOverride(for: variant)
        let isCustom = override != nil

        VStack(alignment: .leading, spacing: 10) {
            // Default preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)
                    Spacer()
                    if isCustom {
                        Button("Reset to Default") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                overrides.resetSystemPrompt(for: variant)
                                saveImmediately()
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                    }
                }

                Text(PromptOverrides.defaultSystemPrompt(for: variant))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isCustom ? .ypText4 : .ypText2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .opacity(isCustom ? 0.6 : 1.0)
            }

            // Custom editor
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CUSTOM")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)
                    Spacer()
                    if !isCustom {
                        Button("Customize") {
                            overrides.setSystemPrompt(
                                PromptOverrides.defaultSystemPrompt(for: variant),
                                for: variant,
                                isEnabled: true
                            )
                            saveImmediately()
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.ypLavender)
                    }
                }

                if isCustom {
                    // Toggle
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { overrides.systemPromptOverride(for: variant)?.isEnabled ?? false },
                            set: { newVal in
                                overrides.setSystemPromptEnabled(newVal, for: variant)
                                saveImmediately()
                            }
                        ))
                        .toggleStyle(YPToggleStyle())

                        Text("Use custom prompt for \(variant.displayName)")
                            .font(.system(size: 11))
                            .foregroundColor(.ypText3)
                    }
                    .padding(.bottom, 4)

                    // Text editor
                    TextEditor(text: Binding(
                        get: { overrides.systemPromptOverride(for: variant)?.text ?? "" },
                        set: { newVal in
                            overrides.setSystemPromptText(newVal, for: variant)
                            debounceSave()
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ypText1)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.ypBorder, lineWidth: 1)
                    )
                    .cornerRadius(6)

                    if variant == .unified {
                        Text("App-specific rules and formality modifiers are appended automatically after this prompt.")
                            .font(.system(size: 10))
                            .foregroundColor(.ypText4)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section 2: Few-Shot Examples
    // ═══════════════════════════════════════════════════════════════════

    private var fewShotExamplesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                label: "FEW-SHOT EXAMPLES",
                icon: "list.bullet.rectangle",
                description: "Input/output pairs that teach the AI by example. These are included in the user message."
            )

            // Expandable header
            let hasOverride = overrides.fewShotOverride != nil
            let isEnabled = overrides.fewShotOverride?.isEnabled ?? false
            let exampleCount = overrides.fewShotOverride?.examples.count ?? PromptTemplates.Examples.benchmark.count

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundColor(hasOverride && isEnabled ? .ypLavender : .ypText3)
                        .frame(width: 16)

                    Text("Examples (\(exampleCount))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ypText1)

                    Spacer()

                    overrideBadge(hasOverride: hasOverride, isEnabled: isEnabled)

                    Image(systemName: fewShotExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        fewShotExpanded.toggle()
                    }
                }

                if fewShotExpanded {
                    fewShotEditor
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fewShotExpanded ? Color.white.opacity(0.04) : Color.clear)
            )
        }
    }

    @ViewBuilder
    private var fewShotEditor: some View {
        let isCustom = overrides.fewShotOverride != nil

        VStack(alignment: .leading, spacing: 10) {
            if !isCustom {
                // Show defaults read-only
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEFAULT EXAMPLES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)
                }

                ForEach(Array(PromptTemplates.Examples.benchmark.enumerated()), id: \.offset) { index, example in
                    readOnlyExampleCard(index: index + 1, input: example.input, output: example.output)
                }

                HStack {
                    Spacer()
                    Button("Customize") {
                        overrides.fewShotOverride = .init(
                            isEnabled: true,
                            examples: PromptOverrides.defaultFewShotExamples()
                        )
                        saveImmediately()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.ypLavender)
                }
            } else {
                // Custom mode
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(
                        get: { overrides.fewShotOverride?.isEnabled ?? false },
                        set: { newVal in
                            overrides.fewShotOverride?.isEnabled = newVal
                            saveImmediately()
                        }
                    ))
                    .toggleStyle(YPToggleStyle())

                    Text("Use custom examples")
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)

                    Spacer()

                    Button("Reset to Defaults") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            overrides.fewShotOverride = nil
                            saveImmediately()
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
                }
                .padding(.bottom, 4)

                // Editable example cards
                let examples = overrides.fewShotOverride?.examples ?? []
                ForEach(Array(examples.enumerated()), id: \.element.id) { index, example in
                    editableExampleCard(index: index)
                }

                // Add example button
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            overrides.fewShotOverride?.examples.append(
                                .init(input: "", output: "")
                            )
                            saveImmediately()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                            Text("Add Example")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.ypLavender)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.ypLavender.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                Text("Small models (≤2B) use only the first 3 examples. Medium/large models use all.")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText4)
                    .lineSpacing(2)
            }
        }
    }

    @ViewBuilder
    private func readOnlyExampleCard(index: Int, input: String, output: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Example \(index)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.ypText3)
                Spacer()
            }

            HStack(alignment: .top, spacing: 8) {
                Text("IN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.ypWarm)
                    .frame(width: 24, alignment: .trailing)

                Text(input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ypText2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("OUT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.ypMint)
                    .frame(width: 24, alignment: .trailing)

                Text(output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ypText2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.ypBorderLight, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func editableExampleCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Example \(index + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.ypText3)

                Spacer()

                // Delete button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        guard overrides.fewShotOverride != nil,
                              index < (overrides.fewShotOverride?.examples.count ?? 0) else { return }
                        overrides.fewShotOverride?.examples.remove(at: index)
                        saveImmediately()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.ypRed.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Input field
            HStack(alignment: .top, spacing: 8) {
                Text("IN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.ypWarm)
                    .frame(width: 24, alignment: .trailing)
                    .padding(.top, 7)

                TextEditor(text: Binding(
                    get: { overrides.fewShotOverride?.examples[safe: index]?.input ?? "" },
                    set: { newVal in
                        guard overrides.fewShotOverride != nil,
                              index < (overrides.fewShotOverride?.examples.count ?? 0) else { return }
                        overrides.fewShotOverride?.examples[index].input = newVal
                        debounceSave()
                    }
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ypText1)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.ypBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }

            // Output field
            HStack(alignment: .top, spacing: 8) {
                Text("OUT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.ypMint)
                    .frame(width: 24, alignment: .trailing)
                    .padding(.top, 7)

                TextEditor(text: Binding(
                    get: { overrides.fewShotOverride?.examples[safe: index]?.output ?? "" },
                    set: { newVal in
                        guard overrides.fewShotOverride != nil,
                              index < (overrides.fewShotOverride?.examples.count ?? 0) else { return }
                        overrides.fewShotOverride?.examples[index].output = newVal
                        debounceSave()
                    }
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ypText1)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.ypBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.ypLavender.opacity(0.15), lineWidth: 1)
        )
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section 3: App-Specific Rules
    // ═══════════════════════════════════════════════════════════════════

    private var appSpecificRulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                label: "APP-SPECIFIC RULES",
                icon: "app.badge",
                description: "Per-category formatting rules injected into the system prompt based on the active app."
            )

            VStack(spacing: 2) {
                ForEach(PromptOverrides.editableCategories) { category in
                    categoryRow(category)
                }
            }

            // Reset button
            if !overrides.categories.isEmpty {
                HStack {
                    Spacer()
                    Button("Reset All App Rules") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            overrides.categories.removeAll()
                            expandedCategory = nil
                            saveImmediately()
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Category Row (existing pattern, refined)

    @ViewBuilder
    private func categoryRow(_ category: AppCategory) -> some View {
        let isExpanded = expandedCategory == category
        let hasOverride = overrides.categories[category.rawValue] != nil
        let isEnabled = overrides.categories[category.rawValue]?.isEnabled ?? false

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(hasOverride && isEnabled ? .ypLavender : .ypText3)
                    .frame(width: 16)

                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ypText1)

                Spacer()

                overrideBadge(hasOverride: hasOverride, isEnabled: isEnabled)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedCategory = isExpanded ? nil : category
                }
            }

            if isExpanded {
                categoryEditor(category)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isExpanded ? Color.white.opacity(0.04) : Color.clear)
        )
    }

    @ViewBuilder
    private func categoryEditor(_ category: AppCategory) -> some View {
        let currentOverride = overrides.categories[category.rawValue]
        let isCustom = currentOverride != nil

        VStack(alignment: .leading, spacing: 10) {
            // Default rules preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)
                    Spacer()
                    if isCustom {
                        Button("Reset to Default") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                overrides.categories.removeValue(forKey: category.rawValue)
                                saveImmediately()
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                    }
                }

                Text(PromptOverrides.defaultRules(for: category))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isCustom ? .ypText4 : .ypText2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .opacity(isCustom ? 0.6 : 1.0)
            }

            // Custom override editor
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CUSTOM")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)
                    Spacer()
                    if !isCustom {
                        Button("Customize") {
                            overrides.categories[category.rawValue] = .init(
                                rules: PromptOverrides.defaultRules(for: category),
                                isEnabled: true
                            )
                            saveImmediately()
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.ypLavender)
                    }
                }

                if isCustom {
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { overrides.categories[category.rawValue]?.isEnabled ?? false },
                            set: { newVal in
                                overrides.categories[category.rawValue]?.isEnabled = newVal
                                saveImmediately()
                            }
                        ))
                        .toggleStyle(YPToggleStyle())

                        Text("Use custom rules for \(category.displayName)")
                            .font(.system(size: 11))
                            .foregroundColor(.ypText3)
                    }
                    .padding(.bottom, 4)

                    TextEditor(text: Binding(
                        get: { overrides.categories[category.rawValue]?.rules ?? "" },
                        set: { newVal in
                            overrides.categories[category.rawValue]?.rules = newVal
                            debounceSave()
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ypText1)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.ypBorder, lineWidth: 1)
                    )
                    .cornerRadius(6)

                    Text("Use - prefixed lines for rules (e.g. \"- Keep @mentions exactly\"). These get added to the system prompt.")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText4)
                        .lineSpacing(2)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Shared Components
    // ═══════════════════════════════════════════════════════════════════

    @ViewBuilder
    private func sectionHeader(label: String, icon: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.ypText3)

                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.ypText3)
                    .tracking(0.8)
            }

            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .lineSpacing(2)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func overrideBadge(hasOverride: Bool, isEnabled: Bool) -> some View {
        if hasOverride && isEnabled {
            Text("Custom")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ypLavender)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.ypLavender.opacity(0.12))
                .cornerRadius(4)
        } else {
            Text("Default")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ypText4)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
