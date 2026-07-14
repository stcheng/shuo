import Foundation

struct ResolvedProjectDirectory {
    let url: URL
    let bookmarkIsStale: Bool
    let requiresSecurityScope: Bool
}

enum ProjectDirectoryBookmark {
    static func makeBookmarkData(for directoryURL: URL) throws -> Data {
        let standardizedURL = directoryURL.standardizedFileURL
        guard AppRuntime.isSandboxed else {
            return try standardizedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        return try standardizedURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ project: LinkedProjectVocabulary) throws -> ResolvedProjectDirectory {
        guard let bookmarkData = project.bookmarkData else {
            return ResolvedProjectDirectory(
                url: URL(fileURLWithPath: project.lastKnownPath, isDirectory: true).standardizedFileURL,
                bookmarkIsStale: false,
                requiresSecurityScope: false
            )
        }

        var isStale = false
        let options: URL.BookmarkResolutionOptions = AppRuntime.isSandboxed ? .withSecurityScope : []
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedProjectDirectory(
            url: resolvedURL.standardizedFileURL,
            bookmarkIsStale: isStale,
            requiresSecurityScope: AppRuntime.isSandboxed
        )
    }
}
