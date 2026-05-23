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

    weak var undoManager: UndoManager?

    init() {
        self.text = ""
        self.initialByteSize = 0
    }

    init(file: FileWrapper, contentType: UTType) throws {
        let bytes = file.regularFileContents ?? Data()
        guard let decoded = String(data: bytes, encoding: .utf8) else {
            throw DocumentError.invalidEncoding
        }
        self.text = decoded
        self.initialByteSize = bytes.count
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
