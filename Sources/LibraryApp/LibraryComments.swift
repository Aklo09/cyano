import Foundation
import LibraryCore

/// The inspector's tabs, in the same positions for every kind (screen specs, "Inspector").
public enum InspectorTab: String, CaseIterable, Sendable {
    case statistics, details, comments

    public var title: String {
        switch self {
        case .statistics: "Statistics"
        case .details: "Details"
        case .comments: "Comments"
        }
    }
}

/// Whose comments the inspector shows: a saved item's root or one of its book entries (stored indices).
public struct CommentScope: Equatable, Hashable, Sendable {
    public let itemId: String
    public let entryPath: [Int]

    var key: String { itemId + ":" + BlueprintEntryReader.pathText(entryPath) }
}

/// Comments are plain text of at most 64 KiB UTF-8 (storage contract).
public let commentByteLimit = 64 * 1024

extension LibraryBrowserModel {
    /// The selected item's root, the selected entry in an open book, or the open book itself (COM-1).
    public var commentScope: CommentScope? {
        if let book, !isFiltering {
            if selection.isEmpty { return CommentScope(itemId: book.itemId, entryPath: book.path) }
            guard selection.count == 1, let row = selectedRows.first, let path = row.entryPath else { return nil }
            return CommentScope(itemId: book.itemId, entryPath: path)
        }
        guard let item = selectedItem else { return nil }
        return CommentScope(itemId: item.id, entryPath: [])
    }

    /// The scope's comments, oldest first (COM-1, COM-7).
    public var comments: [LibraryComment] {
        guard let scope = commentScope,
            let item = listing?.items.first(where: { $0.id == scope.itemId })
        else { return [] }
        return item.metadata.comments.filter { $0.entryPath == scope.entryPath }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The draft for the current scope; each item and entry keeps its own, so text never moves to another one.
    public var commentDraft: String {
        get { commentScope.flatMap { commentDrafts[$0.key] } ?? "" }
        set { if let scope = commentScope { commentDrafts[scope.key] = newValue } }
    }

    public var commentTooLong: Bool { commentDraft.utf8.count > commentByteLimit }

    /// Adding needs text that is not only whitespace and fits the limit (COM-4, COM-5).
    public var canAddComment: Bool {
        commentScope != nil && !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !commentTooLong && !addingComment
    }

    /// Saves the draft as a comment on the current scope; the text stays when saving fails (COM-3).
    public func addComment() async {
        guard canAddComment, let scope = commentScope else { return }
        let text = commentDraft
        addingComment = true
        defer { addingComment = false }
        commentFailure = nil
        let outcome = await session.perform(.commenting) {
            try $0.addComment(id: scope.itemId, entryPath: scope.entryPath, text: text)
        }
        switch outcome {
        case .success:
            commentDrafts[scope.key] = nil
        case .failure(let message):
            commentFailure = message
        case .ignored:
            break
        }
    }

    /// Deletes a comment after the owner confirmed it (COM-6).
    public func deleteComment(_ comment: LibraryComment) async {
        guard let scope = commentScope else { return }
        commentFailure = nil
        let outcome = await session.perform(.changing) {
            try $0.deleteComment(id: scope.itemId, commentId: comment.id)
        }
        if case .failure(let message) = outcome { commentFailure = message }
    }

    /// Add Comment (⌥⌘K): shows the Comments tab and moves focus to the field.
    public func beginComment() {
        guard commentScope != nil else { return }
        inspectorTab = .comments
        commentFocusRequested = true
    }
}
