import AppKit
import SwiftUI

struct QuestionView: View {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    let question: Question
    @Binding var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question.text)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            switch question.type {
            case .freeText:
                freeTextInput
            case .multipleChoice:
                multipleChoiceInput
            }
        }
        .onAppear {
            print("\(debugMarker) QuestionView appeared id=\(question.id) type=\(question.type)")
        }
    }

    private var freeTextInput: some View {
        TransparentTextEditor(text: $answer)
            .frame(height: 120)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
    }

    private var multipleChoiceInput: some View {
        VStack(spacing: 12) {
            ForEach(question.choices ?? [], id: \.self) { choice in
                Button {
                    print("\(debugMarker) QuestionView choice selected questionId=\(question.id) choice=\(choice)")
                    answer = choice
                } label: {
                    HStack {
                        Text(choice)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if answer == choice {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(12)
                    .background(answer == choice ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - TransparentTextEditor

/// NSTextView wrapper with a transparent background, replacing TextEditor + .scrollContentBackground(.hidden)
/// which requires macOS 13+.
private struct TransparentTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
