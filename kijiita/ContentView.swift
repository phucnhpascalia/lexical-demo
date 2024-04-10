import Combine
import EditorHistoryPlugin
import Foundation
import Lexical
import LexicalInlineImagePlugin
import LexicalLinkPlugin
import SwiftUI

struct ContentView: View {
    @StateObject var store = LexicalStore()
    @State private var showingPopover = false
    @State private var username: String = ""

    @FocusState private var keyboardFocused: Bool

    var body: some View {
        VStack {
            ScrollView {
                Text("Kijiita")
                    .popover(isPresented: $showingPopover) {
                        ZStack {
                            Color.yellow.opacity(0.7)
                                .edgesIgnoringSafeArea(.all)
                            HStack {
                                Button(action: {
                                    print("memo")
                                }) {
                                    Text("memo")
                                        .bold()
                                        .padding()
                                        .background(Color.white)
                                        .foregroundColor(.yellow)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 25)
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                }
                                .frame(maxHeight: 20)
                                .background(Color.yellow)
                                .cornerRadius(80)
                                .padding(.leading, 10)

                                Spacer()
                            }

                            HStack {
                                let formatingDate = getFormattedDate(date: Date(), format: "yyyy/MM/dd HH:MM")
                                Text(formatingDate).font(.system(size: 12)).foregroundColor(Color.black.opacity(0.7))
                            }

                            HStack {
                                Spacer()
                                Button(action: {
                                    print("setting")
                                }) {
                                    Text("setting")
                                        .bold()
                                        .padding()
                                        .foregroundColor(Color.black)
                                }
                                .frame(maxHeight: 20)
                                .padding(.trailing, 10)
                            }
                        }
                        .frame(maxHeight: 50)
                        Spacer()

                        TextField(
                            "Title",
                            text: $username
                        )
                        .padding()
                        LexicalText(store: store)
                    }
            }
        }

        VStack(spacing: 0) {
            Button("Create memo", systemImage: "pencil") {
                showingPopover = true
            }
            .foregroundColor(Color.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            Color.white
        )
        .cornerRadius(20, corners: .topLeft)
        .cornerRadius(20, corners: .topRight)
        .shadow(color: Color.gray.opacity(0.7), radius: 8, x: 0, y: 0)
        .mask(Rectangle().padding(.top, -20))
    }

    func getFormattedDate(date: Date, format: String) -> String {
        let dateformat = DateFormatter()
        dateformat.dateFormat = format
        return dateformat.string(from: date)
    }
}

class LexicalStore: ObservableObject {
    weak var view: LexicalView?
    let theme: Theme

    @Published var isBold = false
    @Published var isItalic = false

    init() {
        theme = Theme()
        theme.paragraph = [
            .fontSize: 18.0,
            .lineHeight: 18.0,
        ]
        theme.link = [
            .foregroundColor: UIColor.systemBlue,
        ]
    }

    var editorState: EditorState? {
        view?.editor.getEditorState()
    }

    var editor: Editor? {
        view?.editor
    }

    func dispatchCommand(type: CommandType, payload: Any?) {
        view?.editor.dispatchCommand(type: type, payload: payload)
    }

    func update(closure: @escaping () throws -> Void) throws {
        try view?.editor.update(closure)
    }
}

struct LexicalText: UIViewRepresentable {
    public var store: LexicalStore

    func makeUIView(context _: Context) -> UIStackView {
        // Create a UIStackView
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 8

        let editorHistoryPlugin = EditorHistoryPlugin()
        let imagePlugin = InlineImagePlugin()
        let linkPlugin = LinkPlugin()
        let toolbarPlugin = ToolbarPlugin(historyPlugin: editorHistoryPlugin)

        let view = LexicalView(
            editorConfig: EditorConfig(
                theme: store.theme,
                plugins: [toolbarPlugin, imagePlugin, linkPlugin, editorHistoryPlugin]
            ),
            featureFlags: FeatureFlags(),
            placeholderText: LexicalPlaceholderText(
                text: "Write a new memo",
                font: .systemFont(ofSize: 18),
                color: UIColor.placeholderText
            )
        )

        linkPlugin.lexicalView = view
        store.view = view

        _ = view.editor.registerUpdateListener { _, _, _ in
            updateStoreState()
        }

        stackView.addArrangedSubview(view)
        stackView.addArrangedSubview(toolbarPlugin.toolbar)

        return stackView
    }

    func updateUIView(_ uiView: UIStackView, context _: Context) {
        // Loop through arranged subviews of UIStackView
        for subview in uiView.arrangedSubviews {
            // Check if the subview is an instance of LexicalView
            if let lexicalView = subview as? LexicalView {
                // Now you have access to the LexicalView
                // You can perform any updates or actions on the LexicalView here
                lexicalView.placeholderText = LexicalPlaceholderText(
                    text: "...",
                    font: .systemFont(ofSize: 18),
                    color: UIColor.placeholderText
                )
            }
        }
    }

    func updateStoreState() {
        let rangeSelection = try? getSelection() as? RangeSelection
        if rangeSelection != nil {
            store.isBold = rangeSelection?.hasFormat(type: .bold) ?? false
        }
    }
}

struct ToolbarImage: View {
    var systemName: String
    var active = false

    var body: some View {
        Image(systemName: systemName)
            .resizable().aspectRatio(contentMode: .fit).frame(width: 32, height: 32).padding()
            .background(active ? Color.red : Color.black)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    var keyboardPublisher: AnyPublisher<Bool, Never> {
        Publishers
            .Merge(
                NotificationCenter
                    .default
                    .publisher(for: UIResponder.keyboardWillShowNotification)
                    .map { _ in true },
                NotificationCenter
                    .default
                    .publisher(for: UIResponder.keyboardWillHideNotification)
                    .map { _ in false }
            )
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

