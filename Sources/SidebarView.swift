import SwiftUI

/// A compact, keyboard-friendly navigation sidebar inspired by canvas apps
/// such as Excalidraw. It deliberately reuses Macdraw's page model rather
/// than creating a second document store.
struct SidebarView: View {
    @ObservedObject var state: CanvasState
    @ObservedObject var pages: PagesManager
    let onClose: () -> Void
    let onSwitchPage: (UUID) -> Void
    let onClear: () -> Void
    let onResetView: () -> Void

    @State private var newPageName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.45)
            pageList
            Divider().opacity(0.45)
            quickTools
            Spacer(minLength: 0)
            Divider().opacity(0.45)
            canvasActions
        }
        .frame(width: 292, height: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundStyle(macdrawAccent)
            Text("Workspace")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close sidebar")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PAGES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pages.pages.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(pages.pages) { page in
                        SidebarPageRow(
                            page: page,
                            isCurrent: page.id == pages.currentPageID,
                            canDelete: pages.pages.count > 1,
                            onOpen: { onSwitchPage(page.id) },
                            onRename: { pages.renamePage(id: page.id, to: $0) },
                            onDelete: { pages.deletePage(id: page.id) }
                        )
                    }
                }
            }
            .frame(maxHeight: 218)

            HStack(spacing: 6) {
                TextField("New page", text: $newPageName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .onSubmit(addPage)
                Button(action: addPage) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 28)
                        .background(macdrawAccent, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add page")
            }
        }
        .padding(14)
    }

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK TOOLS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([Tool.selection, .rectangle, .text, .arrow, .freedraw], id: \.self) { tool in
                    Button {
                        if tool != .text { state.lastNonTextTool = tool }
                        state.tool = tool
                        state.drawingMode = true
                    } label: {
                        Image(systemName: tool == .selection ? "cursorarrow" : tool == .text ? "textformat" : tool == .arrow ? "arrow.right" : tool == .freedraw ? "pencil.tip" : "rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 38, height: 32)
                            .background(
                                state.tool == tool ? macdrawAccent.opacity(0.78) : Color.primary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(state.tool == tool ? .white : .primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tool.label)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var canvasActions: some View {
        VStack(spacing: 4) {
            SidebarAction(title: "Reset canvas view", symbol: "arrow.up.left.and.arrow.down.right", action: onResetView)
            SidebarAction(title: "Clear this page", symbol: "trash", destructive: true, action: onClear)
        }
        .padding(10)
    }

    private func addPage() {
        let id = pages.addPage(named: newPageName.trimmingCharacters(in: .whitespacesAndNewlines))
        newPageName = ""
        onSwitchPage(id)
    }
}

private struct SidebarPageRow: View {
    let page: CanvasPage
    let isCurrent: Bool
    let canDelete: Bool
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCurrent ? "doc.fill" : "doc")
                .font(.system(size: 12))
                .foregroundStyle(isCurrent ? macdrawAccent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                if editing {
                    TextField("Page name", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .onSubmit { onRename(draft); editing = false }
                        .onExitCommand { editing = false }
                } else {
                    Text(page.name)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                }
                if !page.note.isEmpty {
                    Text(page.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { draft = page.name; editing = true } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDelete ? Color.secondary : Color.secondary.opacity(0.3))
            .disabled(!canDelete)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .background(isCurrent ? macdrawAccent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { if !isCurrent && !editing { onOpen() } }
    }
}

private struct SidebarAction: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
