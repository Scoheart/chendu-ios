import SwiftUI

/// A built-in margin note, rendered like the site's handwritten annotation.
struct AnnotationCard: View {
    var note: Annotation
    var onClose: () -> Void

    var body: some View {
        let color = Ink.color(note.kind)
        HStack(alignment: .top, spacing: 10) {
            Text("\(note.n)")
                .font(.handEn(18, bold: true))
                .foregroundStyle(Color(color))
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color(color), lineWidth: 1.6))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(note.tag)
                        .font(.system(size: 10))
                        .kerning(0.8)
                        .foregroundStyle(Color(color).opacity(0.8))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(color).opacity(0.7), lineWidth: 1))
                    Text(note.head)
                        .font(.handEn(25, bold: true))
                        .foregroundStyle(Color(color))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(emphasized(note.body, color: color))
                    .font(.handZh(19))
                    .lineSpacing(3)
                    .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("noteBody")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 10, topTrailingRadius: 10)
                .fill(Color(Ink.background(note.kind)))
        )
        .overlay(alignment: .leading) { Rectangle().fill(Color(color)).frame(width: 3) }
        .rotationEffect(.degrees(note.tilt * 0.35))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("annotationCard")
    }
}

/// The reader's own note, shown inline under its paragraph.
struct UserNoteCard: View {
    var note: UserNote
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                Text("我的笔记").font(.handZh(17))
                Spacer()
            }
            .foregroundStyle(Color.userInk)
            Text("“\(note.quote)”")
                .font(.serif(15).italic())
                .foregroundStyle(Color(red: 0.42, green: 0.29, blue: 0.11))
                .lineLimit(3)
            Text(note.text)
                .font(.handZh(20))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button("编辑", systemImage: "square.and.pencil", action: onEdit)
                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                Spacer()
                Button("收起", action: onClose)
            }
            .font(.system(size: 13))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Color.userInk)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Ink.userBG)))
        .overlay(alignment: .leading) { Rectangle().fill(Color(Ink.userHLOn)).frame(width: 3) }
        .accessibilityIdentifier("userNoteCard")
    }
}

struct NoteDraft: Identifiable {
    var id = UUID()
    var existing: UserNote?
    var paragraphIndex: Int
    var range: NSRange
    var quote: String
    var text: String
}

struct NoteEditor: View {
    @State var draft: NoteDraft
    var onSave: (NoteDraft) -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("“\(draft.quote)”")
                    .font(.serif(15).italic())
                    .foregroundStyle(Color.muted)
                    .lineLimit(4)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Color(Ink.userHLOn)).frame(width: 3) }
                TextEditor(text: $draft.text)
                    .font(.system(size: 17))
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.rule))
                    .accessibilityIdentifier("noteTextEditor")
                if let onDelete {
                    Button("删除这条笔记", role: .destructive) { onDelete(); dismiss() }
                        .font(.system(size: 15))
                }
            }
            .padding()
            .background(PaperBackground())
            .navigationTitle(draft.existing == nil ? "加笔记" : "编辑笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(draft); dismiss() }
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveNote")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .tint(Color.userInk)
    }
}
