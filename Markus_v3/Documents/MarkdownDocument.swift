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

    /// open-path-hardening-10 DC-3 — renderer-facing form of the buffer with the
    /// leading UTF-8 BOM (U+FEFF) suppressed. The buffer (`text`) retains the BOM
    /// so a no-edit save round-trips the original bytes; only the display surfaces
    /// drop it so users never see a stray zero-width character or replacement glyph.
    var displayText: String {
        guard text.unicodeScalars.first == "\u{FEFF}" else { return text }
        return String(text.unicodeScalars.dropFirst())
    }

    init() {
        self.text = ""
        self.initialByteSize = 0
        self.lastKnownDiskContent = ""
    }

    init(file: FileWrapper, contentType: UTType) throws {
        let bytes = file.regularFileContents ?? Data()
        // open-path-hardening-10 DC-3 — Apple Foundation's
        // `String(data:encoding:.utf8)` silently strips a leading UTF-8 BOM.
        // To preserve byte-identical save round-trip (BR-1.3) we strip the
        // BOM bytes ourselves, decode, then re-prepend U+FEFF to the buffer.
        let hadBOM = bytes.starts(with: [0xEF, 0xBB, 0xBF])
        let bytesForDecode = hadBOM ? bytes.dropFirst(3) : bytes.subdata(in: 0..<bytes.count)
        guard let decoded = String(data: bytesForDecode, encoding: .utf8) else {
            throw DocumentError.invalidEncoding
        }
        let buffer = hadBOM ? "\u{FEFF}" + decoded : decoded
        self.text = buffer
        self.initialByteSize = bytes.count
        self.lastKnownDiskContent = buffer
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
