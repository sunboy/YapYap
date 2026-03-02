// PromptsTab.swift
// YapYap — Settings tab for viewing and customizing per-category LLM prompts
import SwiftUI
import SwiftData

struct PromptsTab: View {
    @State private var overrides = PromptOverrides()
    @State private var expandedCategory: AppCategory?
    @State private var didLoad = false

    /// Categories that have meaningful prompt rules (skip browser/other which have empty defaults)
    private let editableCategories: [AppCategory] = [
        .personalMessaging, .workMessaging, .email, .codeEditor,
        .aiChat, .terminal, .notes, .social, .documents
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Customize the formatting rules the AI applies when you dictate into each app category.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 4)

            Text("Each category has built-in defaults. You can override them with your own rules.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            // Category list
            VStack(spacing: 2) {
                ForEach(editableCategories) { category in
                    categoryRow(category)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            overrides = PromptOverrides.loadFromUserDefaults()
            didLoad = true
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(_ category: AppCategory) -> some View {
        let isExpanded = expandedCategory == category
        let hasOverride = overrides.categories[category.rawValue] != nil
        let isEnabled = overrides.categories[category.rawValue]?.isEnabled ?? false

        VStack(spacing: 0) {
            // Collapsed header
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(hasOverride && isEnabled ? .ypLavender : .ypText3)
                    .frame(width: 16)

                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ypText1)

                Spacer()

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

            // Expanded editor
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

    // MARK: - Category Editor

    @ViewBuilder
    private func categoryEditor(_ category: AppCategory) -> some View {
        let currentOverride = overrides.categories[category.rawValue]
        let rulesText = currentOverride?.rules ?? PromptOverrides.defaultRules(for: category)
        let isCustom = currentOverride != nil

        VStack(alignment: .leading, spacing: 10) {
            // Default rules preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DEFAULT RULES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)
                    Spacer()
                    if isCustom {
                        Button("Reset to Default") {
                            overrides.categories.removeValue(forKey: category.rawValue)
                            overrides.saveToUserDefaults()
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
                    Text("CUSTOM RULES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ypText4)
                        .tracking(0.8)

                    Spacer()

                    if !isCustom {
                        Button("Customize") {
                            // Initialize override with default rules as starting point
                            overrides.categories[category.rawValue] = .init(
                                rules: PromptOverrides.defaultRules(for: category),
                                isEnabled: true
                            )
                            overrides.saveToUserDefaults()
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.ypLavender)
                    }
                }

                if isCustom {
                    // Toggle
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { overrides.categories[category.rawValue]?.isEnabled ?? false },
                            set: { newVal in
                                overrides.categories[category.rawValue]?.isEnabled = newVal
                                overrides.saveToUserDefaults()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Text("Use custom rules for \(category.displayName)")
                            .font(.system(size: 11))
                            .foregroundColor(.ypText3)
                    }
                    .padding(.bottom, 4)

                    // Editor
                    TextEditor(text: Binding(
                        get: { overrides.categories[category.rawValue]?.rules ?? "" },
                        set: { newVal in
                            overrides.categories[category.rawValue]?.rules = newVal
                            overrides.saveToUserDefaults()
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
}
