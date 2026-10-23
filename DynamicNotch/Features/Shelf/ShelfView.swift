// ShelfView.swift
// DynamicNotch / Features / Shelf
//
// Apple-grade temporary shelf (tray) view hosted inside the expanded notch.
// Supports bidirectional drag-and-drop: ingest files from Desktop/Finder and
// re-drag them into any destination application or space.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {

    @ObservedObject private var manager = ShelfManager.shared
    var onDismiss: (() -> Void)? = nil

    @State private var hoveredItemId: UUID? = nil
    @State private var isTargeted: Bool = false

    private let accentColor = Color(red: 0.22, green: 0.62, blue: 1.0) // Apple System Cyan-Blue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            headerView

            // Content: Empty Drop Zone or Horizontal Item Strip
            if manager.items.isEmpty {
                emptyDropTargetView
            } else {
                itemsScrollView
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.fileURL, .item, .data], isTargeted: $isTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .onChange(of: isTargeted) { _, newValue in
            manager.isDropZoneTargeted = newValue
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accentColor)

            Text("GEÇİCİ DOSYA RAFI")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .tracking(0.6)

            if !manager.items.isEmpty {
                Text("\(manager.items.count)")
                    .font(.system(size: 9.0, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.18))
                    )
            }

            Spacer()

            HStack(spacing: 6) {
                if !manager.items.isEmpty {
                    Button {
                        manager.clearAll()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("Temizle")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.60))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.50))
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Empty State (Drop Target)

    private var emptyDropTargetView: some View {
        let isHighlighted = isTargeted || manager.isDragApproaching || manager.isDropZoneTargeted

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHighlighted ? accentColor.opacity(0.85) : Color.white.opacity(0.16),
                    style: StrokeStyle(lineWidth: isHighlighted ? 1.8 : 1.2, dash: [5, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHighlighted ? accentColor.opacity(0.12) : Color.white.opacity(0.03))
                )

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isHighlighted ? accentColor.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)

                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isHighlighted ? accentColor : .white.opacity(0.70))
                        .scaleEffect(isHighlighted ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: isHighlighted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dosya veya Görseli Buraya Bırakın")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))

                    Text("Farklı bir uygulamaya taşımak için çentikte askıya alın")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 50)
    }

    // MARK: - Populated Shelf Items Strip

    private var itemsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(manager.items) { item in
                    itemCard(for: item)
                }

                // Append Slot for dropping additional files
                appendSlotView
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func itemCard(for item: ShelfItem) -> some View {
        let isHovered = (hoveredItemId == item.id)

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                // Thumbnail or Type Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)

                    if let thumbnail = item.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1.5)
                    } else {
                        Image(systemName: item.systemIconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(accentColor)
                    }
                }

                // File Name
                Text(item.name)
                    .font(.system(size: 10.0, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 66)

                // Size Badge
                Text(item.fileSizeString)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(width: 78, height: 86)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHovered ? accentColor.opacity(0.40) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            // Enable dragging item OUT of the shelf to any destination
            .onDrag {
                let provider = NSItemProvider(object: item.url as NSURL)
                provider.registerDataRepresentation(
                    forTypeIdentifier: localShelfDragTypeIdentifier,
                    visibility: .all
                ) { completion in
                    completion(Data(), nil)
                    return nil
                }
                return provider
            }
            .onTapGesture(count: 2) {
                manager.openFile(item: item)
            }
            .onTapGesture(count: 1) {
                manager.revealInFinder(item: item)
            }

            // Remove Button on Hover
            if isHovered {
                Button {
                    manager.remove(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .background(Circle().fill(Color.black.opacity(0.60)))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredItemId = hovering ? item.id : nil
            }
        }
    }

    private var appendSlotView: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 44, height: 44)

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
            }

            Text("Ekle")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.40))

            Text("Sürükle")
                .font(.system(size: 8.5, weight: .regular))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(width: 64, height: 86)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
        )
    }

    // MARK: - Drop Handling

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            manager.add(urls: [url])
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    let resolvedUrl: URL? = {
                        if let url = data as? URL { return url }
                        if let nsUrl = data as? NSURL { return nsUrl as URL }
                        if let urlData = data as? Data { return URL(dataRepresentation: urlData, relativeTo: nil) }
                        if let str = data as? String { return URL(string: str) }
                        return nil
                    }()
                    if let resolvedUrl = resolvedUrl {
                        DispatchQueue.main.async {
                            manager.add(urls: [resolvedUrl])
                        }
                    }
                }
            }
        }
        return true
    }
}
