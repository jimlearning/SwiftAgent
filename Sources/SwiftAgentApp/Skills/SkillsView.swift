import SwiftUI
import SwiftAgentCore

/// The Skills library view showing all loaded skills.
/// Per §10.1: loads from user/project/system scopes, shows as a library (not marketplace).
public struct SkillsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var skills: [SkillEntry] = []
    @State private var selectedSkill: SkillEntry?
    @State private var showCreator: Bool = false
    @State private var searchText: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with search and create button
            HStack {
                Text("Skills")
                    .font(.uiHeadline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: { showCreator = true }) {
                    Label("Create Skill", systemImage: "plus")
                        .font(.uiCaption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.borderSubtle)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                TextField("Search skills...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.uiBody)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Color.borderSubtle)

            // Skills list
            if selectedSkill == nil {
                skillsList
            } else {
                skillDetail
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color.bgSidebar)
        .onAppear { loadSkills() }
        .sheet(isPresented: $showCreator) {
            SkillCreatorSheet(onSave: { name, desc, scope, body in
                saveSkill(name: name, description: desc, scope: scope, body: body)
                loadSkills()
            })
        }
    }

    // MARK: - Skills List

    private var skillsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSkills) { skill in
                    SkillCard(
                        name: skill.name,
                        description: skill.description,
                        scope: skill.scope,
                        isSelected: false,
                        onTap: { selectedSkill = skill }
                    )
                    Divider().padding(.leading, 12)
                }
                if filteredSkills.isEmpty {
                    Text("No skills found")
                        .font(.uiBody)
                        .foregroundColor(.textTertiary)
                        .padding(.top, 32)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Skill Detail

    private var skillDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button + title
            HStack {
                Button {
                    selectedSkill = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.uiCaption)
                    .foregroundColor(.accentPrimary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Color.borderSubtle)

            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(skill.name)
                                .font(.uiHeadline)
                                .foregroundColor(.textPrimary)
                            Text(skill.scope.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: skill.scope.badgeColor))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: skill.scope.badgeColor).opacity(0.15))
                                )
                        }
                        Text(skill.description)
                            .font(.uiBody)
                            .foregroundColor(.textSecondary)

                        Divider().background(Color.borderSubtle)

                        if let mdContent = skill.markdownBody {
                            Text(mdContent)
                                .font(.codeMono)
                                .foregroundColor(.textPrimary)
                                .textSelection(.enabled)
                        } else {
                            Text("No detailed content available.")
                                .font(.uiCaption)
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Data

    private var filteredSkills: [SkillEntry] {
        if searchText.isEmpty { return skills }
        let q = searchText.lowercased()
        return skills.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    private func loadSkills() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = appViewModel.selectedThread?.workingDirectory
            ?? NSHomeDirectory()

        let userDir = "\(home)/.swiftagent/skills"
        let projectDir = "\(cwd)/.swiftagent/skills"
        let systemDir = "/etc/swiftagent/skills"

        var loaded: [SkillEntry] = []

        // Load from user scope
        loaded.append(contentsOf: loadSkills(from: userDir, scope: .user))

        // Load from project scope
        loaded.append(contentsOf: loadSkills(from: projectDir, scope: .project))

        // Load from system scope
        loaded.append(contentsOf: loadSkills(from: systemDir, scope: .system))

        // Load from Core bundled skills
        let bundled = SkillFileLoader.loadAllManifests(workingDirectory: cwd)
        // Add bundled ones that aren't already present by name
        var seen = Set(loaded.map(\.name))
        for manifest in bundled {
            if seen.insert(manifest.name).inserted {
                loaded.append(SkillEntry(
                    name: manifest.name,
                    description: manifest.description,
                    scope: .system,
                    markdownBody: manifest.markdownBody,
                    sourcePath: manifest.sourcePath
                ))
            }
        }

        self.skills = loaded.sorted { a, b in
            if a.scope != b.scope { return a.scope < b.scope }
            return a.name < b.name
        }
    }

    private func loadSkills(from directory: String, scope: SkillScope) -> [SkillEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory) else { return [] }
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        var skills: [SkillEntry] = []
        for entry in entries {
            let entryPath = "\(directory)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entryPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillMDPath = "\(entryPath)/SKILL.md"
            guard fm.fileExists(atPath: skillMDPath),
                  let content = try? String(contentsOfFile: skillMDPath, encoding: .utf8) else { continue }

            // Parse front matter
            let parsed = parseFrontMatter(content)
            skills.append(SkillEntry(
                name: parsed.name ?? entry,
                description: parsed.description ?? "No description",
                scope: scope,
                markdownBody: parsed.body,
                sourcePath: skillMDPath
            ))
        }
        return skills
    }

    private func parseFrontMatter(_ content: String) -> (name: String?, description: String?, body: String?) {
        guard content.hasPrefix("---") else {
            // No front matter, treat entire content as body
            return (nil, nil, content)
        }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return (nil, nil, content) }

        var parsedName: String?
        var parsedDesc: String?
        let frontMatter = parts[1]
        for line in frontMatter.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                parsedName = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("description:") {
                parsedDesc = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }

        let bodyContent = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
        return (parsedName, parsedDesc, bodyContent.isEmpty ? nil : bodyContent)
    }

    private func saveSkill(name: String, description: String, scope: SkillScope, body: String) {
        let fm = FileManager.default
        let dir: String
        switch scope {
        case .user:
            dir = "\(fm.homeDirectoryForCurrentUser.path)/.swiftagent/skills/\(name)"
        case .project:
            dir = "\(fm.currentDirectoryPath)/.swiftagent/skills/\(name)"
        case .system:
            dir = "/etc/swiftagent/skills/\(name)"
        }

        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let frontMatter = """
---
name: \(name)
description: \(description)
---

"""
            let fullContent = frontMatter + body
            try fullContent.write(toFile: "\(dir)/SKILL.md", atomically: true, encoding: .utf8)
        } catch {
            print("[SkillsView] Failed to save skill: \(error)")
        }
    }
}

// MARK: - SkillEntry

public struct SkillEntry: Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let scope: SkillScope
    public let markdownBody: String?
    public let sourcePath: String

    public init(name: String, description: String, scope: SkillScope, markdownBody: String?, sourcePath: String) {
        self.id = name
        self.name = name
        self.description = description
        self.scope = scope
        self.markdownBody = markdownBody
        self.sourcePath = sourcePath
    }
}

// Needed for SkillCreatorSheet
extension SkillScope: Hashable {}
