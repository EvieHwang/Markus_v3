import SwiftUI

@main
struct Markus_v3App: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { configuration in
            DocumentView(configuration: configuration)
        }
    }
}
