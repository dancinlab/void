import AppKit
import VoidKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Initialize a pasteboard type from a MIME type string
    init?(mimeType: String) {
        // Explicit mappings for common MIME types
        switch mimeType {
        case "text/plain":
            self = .string
            return
        default:
            break
        }

        // Try to get UTType from MIME type
        guard let utType = UTType(mimeType: mimeType) else {
            // Fallback: use the MIME type directly as identifier
            self.init(mimeType)
            return
        }

        // Use the UTType's identifier
        self.init(utType.identifier)
    }
}

extension NSPasteboard {
    /// The pasteboard to used for Void selection.
    static var voidSelection: NSPasteboard = {
        NSPasteboard(name: .init("com.dancinlab.void.selection"))
    }()

    /// Gets the contents of the pasteboard as a string following a specific set of semantics.
    /// Does these things in order:
    /// - Tries to get the absolute filesystem path of the file in the pasteboard if there is one and ensures the file path is properly escaped.
    /// - Tries to get any string from the pasteboard.
    /// If all of the above fail, returns None.
    func getOpinionatedStringContents() -> String? {
        if let urls = readObjects(forClasses: [NSURL.self]) as? [URL],
           urls.count > 0 {
            return urls
                .map { $0.isFileURL ? VD.Shell.escape($0.path) : $0.absoluteString }
                .joined(separator: " ")
        }

        return self.string(forType: .string)
    }

    /// The pasteboard for the Void enum type.
    static func void(_ clipboard: void_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case VOID_CLIPBOARD_STANDARD:
            return Self.general

        case VOID_CLIPBOARD_SELECTION:
            return Self.voidSelection

        default:
            return nil
        }
    }
}
