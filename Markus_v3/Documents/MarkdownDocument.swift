import Combine
import SwiftUI
import UniformTypeIdentifiers

final class MarkdownDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static let readableContentTypes: [UTType] = {
        var types: [UTType] = []
        if let standard = UTType("public.markdown") {
            types.append(standard)
        }
        if let dfb = UTType("net.daringfireball.markdown") {
            types.append(dfb)
        }
        return types
    }()

    @Published var text: String
    let initialByteSize: Int

    /// DC-9 — the bytes Markus last *wrote to* or last *read from* disk for this
    /// document. The single shared reference both the save bridge (updates after a
    /// successful write) and the change detector (updates after an absorb / a
    /// resolution) keep in agreement, and from which clean/dirty is derived. On
    /// load it equals the just-read content, so a freshly opened buffer is clean.
    var lastKnownDiskContent: String

    weak var undoManager: UndoManager?

    /// DC-10 — clean iff the buffer equals last-known-disk under the equality gate
    /// (DC-11), independent of edit history. This — not the undo manager — is the
    /// authority for collision decisions.
    var isCleanAgainstDisk: Bool {
        ContentEqualityGate.equal(text, lastKnownDiskContent)
    }

    init() {
        self.text = ""
        self.initialByteSize = 0
        self.lastKnownDiskContent = ""
    }

    init(file: FileWrapper, contentType: UTType) throws {
        let bytes = file.regularFileContents ?? Data()
        guard let decoded = String(data: bytes, encoding: .utf8) else {
            throw DocumentError.invalidEncoding
        }
        self.text = decoded
        self.initialByteSize = bytes.count
        self.lastKnownDiskContent = decoded
    }

    convenience init(configuration: ReadConfiguration) throws {
        try self.init(file: configuration.file, contentType: configuration.contentType)
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        text
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        makeFileWrapper(forSnapshot: snapshot)
    }

    func makeFileWrapper(forSnapshot snapshot: Snapshot) -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    func markDirty() {
        undoManager?.registerUndo(withTarget: self) { _ in }
    }
}
