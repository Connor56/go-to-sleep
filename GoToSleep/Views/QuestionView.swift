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
        TextEditor(text: $answer)
            .font(.body)
            .padding(8)
            .frame(height: 120)
            .scrollContentBackground(.hidden)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .foregroundColor(.white)
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
