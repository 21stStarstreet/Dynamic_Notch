// DragDropMonitor.swift
// DynamicNotch / Features / Shelf
//
// Native macOS CoreDrag & Drop Overlay Engine.
// Uses AppKit NSDraggingDestination with selective NSView.hitTest filtering
// to deliver seamless file drop ingestion without false positives or click interference.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

public let localShelfDragTypeIdentifier = "com.dynamicnotch.shelf.item"

public extension NSPasteboard.PasteboardType {
    static let shelfLocalDrag = NSPasteboard.PasteboardType(localShelfDragTypeIdentifier)
}

public extension NSPasteboard {
    var isShelfLocalDrag: Bool {
        availableType(from: [.shelfLocalDrag]) != nil ||
        pasteboardItems?.contains { $0.data(forType: .shelfLocalDrag) != nil } == true
    }

    func extractDroppedURLs() -> [URL] {
        var results: [URL] = []

        // Method 1: readObjects for NSURL with urlReadingFileURLsOnly
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            results.append(contentsOf: urls.filter(\.isFileURL))
        }

        // Method 2: readObjects without options
        if results.isEmpty, let urls = readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            results.append(contentsOf: urls.filter(\.isFileURL))
        }

        // Method 3: pasteboardItems reading .fileURL or .URL or public.file-url
        if results.isEmpty, let items = pasteboardItems {
            for item in items {
                if let str = item.string(forType: .fileURL), let url = URL(string: str), url.isFileURL {
                    results.append(url)
                } else if let str = item.string(forType: .URL), let url = URL(string: str), url.isFileURL {
                    results.append(url)
                } else if let str = item.string(forType: NSPasteboard.PasteboardType("public.file-url")), let url = URL(string: str), url.isFileURL {
                    results.append(url)
                }
            }
        }

        // Method 4: NSFilenamesPboardType (standard Finder drag type)
        if results.isEmpty, let paths = propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            results.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
        }

        var seen = Set<String>()
        return results.filter { seen.insert($0.path).inserted }
    }

    var containsDraggableFiles: Bool {
        if !extractDroppedURLs().isEmpty { return true }
        if canReadObject(forClasses: [NSURL.self], options: nil) { return true }
        if let types = types {
            for type in types {
                if type == .fileURL ||
                   type == .URL ||
                   type.rawValue == "NSFilenamesPboardType" ||
                   type.rawValue == "public.file-url" ||
                   type.rawValue == "com.apple.finder.node" {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Native Drag Destination NSView (Deactivated)

final class DragAndDropView: NSView {
    weak var viewModel: NotchViewModel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func registerTypes() {
        unregisterDraggedTypes()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {}

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}
}

// MARK: - SwiftUI Representable & Overlay (Deactivated)

struct DragAndDropDestinationView: NSViewRepresentable {
    weak var viewModel: NotchViewModel?

    func makeNSView(context: Context) -> DragAndDropView {
        DragAndDropView()
    }

    func updateNSView(_ nsView: DragAndDropView, context: Context) {}
}

struct NotchDragAndDropDestinationOverlay: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        EmptyView()
    }
}

// MARK: - Backward Compatibility Stub

@MainActor
final class DragDropMonitor: ObservableObject {
    static let shared = DragDropMonitor()
    var onDragApproachingNotch: (() -> Void)?
    var onDragEndedOrExited: (() -> Void)?
    private init() {}
    func startMonitoring() {}
    func stopMonitoring() {}
}
