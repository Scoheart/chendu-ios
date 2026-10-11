import SwiftData
import SwiftUI

struct MyNotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\UserNote.issueDate, order: .reverse), SortDescriptor(\UserNote.createdAt)])
    private var notes: [UserNote]
    @State private var copied = false
    @State private var editing: UserNote?
    @State private var editText = ""

    private var groups: [(date: String, title: String, notes: [UserNote])] {
        var order: [String] = []
        var map: [String: [UserNote]] = [:]
        for n in notes where n.deletedAt == nil {
            if map[n.issueDate] == nil { order.append(n.issueDate) }
            map[n.issueDate, default: []].append(n)
        }
        return order.map { d in
            let items = map[d]!.sorted { ($0.paragraphIndex, $0.start) < ($1.paragraphIndex, $1.start) }
            return (d, items.first?.issueTitle ?? "", items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("还没有笔记", systemImage: "pencil.and.scribble")
                    } description: {
                        Text("读文章时长按选中一段原文，在菜单里点「加笔记」。")
                    }
                } else {
                    List {
                        ForEach(groups, id: \.date) { group in
                            Section {
                                ForEach(group.notes) { note in
                                    NavigationLink(value: ReaderRoute(date: note.issueDate, focusNote: note.id)) {
                                        row(note)
                                    }
                                    .listRowBackground(Color.white)
                                    .contextMenu {
                                        Button("复制笔记", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
                                        Button("复制原文和笔记", systemImage: "text.quote") {
                                            UIPasteboard.general.string = "> \(note.quote)\n\n\(note.text)"
                                        }
                                        Button("编辑", systemImage: "square.and.pencil") { editText = note.text; editing = note }
                                        Button("删除", systemImage: "trash", role: .destructive) { delete(note) }
                                    }
                                    .swipeActions {
                                        Button("删除", role: .destructive) { delete(note) }
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.date).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(Color.muted)
                                    Text(group.title).font(.serif(15, weight: .semibold)).foregroundStyle(Color.ink).textCase(nil)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(PaperBackground())
            .navigationTitle("我的笔记")
            .navigationDestination(for: ReaderRoute.self) { r in ReaderView(date: r.date, focusNote: r.focusNote) }
            .toolbar {
                if !groups.isEmpty {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = NotesExport.markdown(notes.filter { $0.deletedAt == nil })
                            copied = true
                        } label: { Image(systemName: "doc.on.doc") }
                            .accessibilityLabel("复制全部笔记")
                        ShareLink(item: NotesExport.markdown(notes.filter { $0.deletedAt == nil }), subject: Text("晨读 · 我的笔记"), preview: SharePreview("晨读 · 我的笔记"))
                            .accessibilityLabel("导出笔记")
                    }
                }
            }
            .alert("已复制全部笔记（Markdown）", isPresented: $copied) { Button("好") {} }
            .sheet(item: $editing) { note in
                NoteEditor(
                    draft: NoteDraft(existing: note, paragraphIndex: note.paragraphIndex, range: NSRange(location: note.start, length: note.length), quote: note.quote, text: note.text),
                    onSave: { d in
                        note.text = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        note.updatedAt = .now
                        try? context.save()
                    },
                    onDelete: { delete(note) }
                )
            }
            .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        }
    }

    private func row(_ note: UserNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("“\(note.quote)”").font(.serif(15).italic()).foregroundStyle(Color(red: 0.42, green: 0.29, blue: 0.11)).lineLimit(3)
            Text(note.text).font(.system(size: 16)).foregroundStyle(Color.ink)
            Text(note.updatedAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(Color.muted)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("myNoteRow")
    }

    private func delete(_ note: UserNote) {
        note.markDeleted()
        try? context.save()
    }
}
