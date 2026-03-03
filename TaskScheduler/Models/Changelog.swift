import Foundation

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let sections: [Section]

    struct Section: Identifiable {
        let id = UUID()
        let category: String
        let items: [String]
    }
}

/// Fetches and parses the CHANGELOG.md from GitHub.
final class ChangelogService: ObservableObject {
    static let shared = ChangelogService()

    @Published private(set) var entries: [ChangelogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasFetched = false

    private let repoOwner = "kibermaks"
    private let repoName = "TaskScheduler"
    private let cacheKey = "TaskScheduler.CachedChangelog"

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    init() {
        if let cached = UserDefaults.standard.string(forKey: cacheKey) {
            entries = Self.parse(cached)
        }
    }

    func fetchIfNeeded() {
        guard !hasFetched, !isLoading else { return }
        fetch()
    }

    func fetch() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer {
                Task { @MainActor in self.isLoading = false; self.hasFetched = true }
            }
            do {
                guard let url = URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/CHANGELOG.md") else { return }
                let (data, response) = try await urlSession.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let markdown = String(data: data, encoding: .utf8) else { return }

                let parsed = Self.parse(markdown)
                await MainActor.run {
                    UserDefaults.standard.set(markdown, forKey: self.cacheKey)
                    self.entries = parsed
                }
            } catch {
                // Silently fail – cached entries remain
            }
        }
    }

    // MARK: - Parser

    static func parse(_ markdown: String) -> [ChangelogEntry] {
        var results: [ChangelogEntry] = []
        let lines = markdown.components(separatedBy: "\n")

        var currentVersion: String?
        var currentDate: String?
        var currentSections: [ChangelogEntry.Section] = []
        var currentCategory: String?
        var currentItems: [String] = []

        func flushCategory() {
            if let cat = currentCategory, !currentItems.isEmpty {
                currentSections.append(.init(category: cat, items: currentItems))
            }
            currentCategory = nil
            currentItems = []
        }

        func flushVersion() {
            flushCategory()
            if let version = currentVersion, let date = currentDate, !currentSections.isEmpty {
                results.append(ChangelogEntry(version: version, date: date, sections: currentSections))
            }
            currentVersion = nil
            currentDate = nil
            currentSections = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Version header: ## [1.10] - 2026-02-27
            if trimmed.hasPrefix("## [") {
                flushVersion()
                let stripped = trimmed.dropFirst(4) // remove "## ["
                let parts = stripped.split(separator: "]", maxSplits: 1)
                if let versionPart = parts.first {
                    currentVersion = String(versionPart)
                }
                if parts.count > 1 {
                    let datePart = parts[1].trimmingCharacters(in: .whitespaces)
                    if datePart.hasPrefix("- ") {
                        currentDate = String(datePart.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    }
                }
                continue
            }

            // Section header: ### Added, ### Changed, etc.
            if trimmed.hasPrefix("### ") {
                flushCategory()
                currentCategory = String(trimmed.dropFirst(4))
                continue
            }

            // List item: - Some change
            if trimmed.hasPrefix("- ") && currentCategory != nil {
                currentItems.append(String(trimmed.dropFirst(2)))
                continue
            }

            // Stop parsing at the horizontal rule before notes section
            if trimmed == "---" {
                break
            }
        }

        flushVersion()
        return results
    }

    // MARK: - Helpers

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
