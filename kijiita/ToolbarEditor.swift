import EditorHistoryPlugin
import Foundation
import Lexical
import LexicalInlineImagePlugin
import LexicalLinkPlugin
import LexicalListPlugin
import SelectableDecoratorNode
import UIKit

public class ToolbarPlugin: Plugin {
    private var _toolbar: UIToolbar

    weak var editor: Editor?
    weak var historyPlugin: EditorHistoryPlugin?

    init(historyPlugin: EditorHistoryPlugin?) {
        _toolbar = UIToolbar()
        self.historyPlugin = historyPlugin
        setUpToolbar()
        // Add observers for keyboard events
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        // Remove observers when view controller is deallocated
        NotificationCenter.default.removeObserver(self)
    }

    // Function to handle keyboard will show event
    @objc private func keyboardWillShow(notification _: Notification) {
        toolbar.isHidden = false
    }

    // Function to handle keyboard will hide event
    @objc private func keyboardWillHide(notification _: Notification) {
        toolbar.isHidden = true
    }

    public func setUp(editor: Editor) {
        self.editor = editor

        _ = editor.registerUpdateListener { [weak self] _, _, _ in
            if let self {
                self.updateToolbar()
            }
        }

        _ = editor.registerCommand(type: .linkTapped) { [weak self] payload in
            if let self, let payload = payload as? URL, let rangeSelection = try? getSelection() as? RangeSelection, let startSearch = try? self.getSelectedNode(selection: rangeSelection) {
                guard let link = getNearestNodeOfType(node: startSearch, type: .link) else {
                    return false
                }

                guard let element = link.getParent() else {
                    return false
                }
                var newSelection: RangeSelection?
                if let index = link.getIndexWithinParent() {
                    newSelection = try? element.select(anchorOffset: index, focusOffset: index + 1)
                }
                guard let selection = newSelection else {
                    return false
                }

                _ = self.showLinkActionSheet(url: payload.absoluteString, selection: selection)
                return true
            }
            return false // shouldn't happen!
        }
    }

    public func tearDown() {}

    // MARK: - Public accessors

    public var toolbar: UIToolbar {
        _toolbar
    }

    // MARK: - Private helpers

    var heading1Button: UIBarButtonItem?

    var paragraphButton: UIBarButtonItem?
    var stylingButton: UIBarButtonItem?
    var linkButton: UIBarButtonItem?
    var increaseIndentButton: UIBarButtonItem?
    var decreaseIndentButton: UIBarButtonItem?
    var insertImageButton: UIBarButtonItem?

    private func setUpToolbar() {
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 10

        let heading1Image = UIImage(named: "fa-heading")
        let resizedImage = heading1Image?.resized(to: CGSize(width: 20, height: 20))
        let heading2Image = UIImage(named: "fa-heading")
        let resizedImage2 = heading2Image?.resized(to: CGSize(width: 15, height: 15))
        let plusImage = UIImage(named: "fa-plus")
        let resizedPlusImage = plusImage?.resized(to: CGSize(width: 20, height: 20))

        let link = UIBarButtonItem(image: UIImage(systemName: "link"), style: .plain, target: self, action: #selector(link))
        let insertImage = UIBarButtonItem(image: UIImage(systemName: "photo"), menu: imageMenu)
        let heading1 = UIBarButtonItem(image: resizedImage, style: .plain, target: self, action: #selector(createHeading1Node))
        let heading2 = UIBarButtonItem(image: resizedImage2, style: .plain, target: self, action: #selector(createHeading2Node))
        let bold = UIBarButtonItem(image: UIImage(systemName: "bold"), style: .plain, target: self, action: #selector(toggleBold))
        let quote = UIBarButtonItem(image: UIImage(systemName: "quote.opening"), style: .plain, target: self, action: #selector(createQuoteNodeWrap))
        let plus = UIBarButtonItem(image: resizedPlusImage, style: .plain, target: self, action: nil)

        let textItem = UIBarButtonItem(title: "56文字", style: .plain, target: nil, action: nil)
        textItem.isEnabled = false

        let items: [UIBarButtonItem] = [insertImage, heading1, heading2, link, bold, quote, plus]
        for item in items {
            item.tintColor = UIColor.gray
        }

        var toolbarItems: [UIBarButtonItem] = []
        for (index, item) in items.enumerated() {
            toolbarItems.append(item)
            if index < items.count - 1 {
                toolbarItems.append(flexibleSpace)
            }
        }

        let dividerLabel = UILabel()
        dividerLabel.text = "|"
        dividerLabel.textColor = .gray
        dividerLabel.sizeToFit()

        let dividerContainerView = UIView(frame: CGRect(x: 0, y: 0, width: dividerLabel.bounds.width, height: dividerLabel.bounds.height))

        dividerLabel.frame = dividerContainerView.bounds
        dividerContainerView.addSubview(dividerLabel)

        let dividerItem = UIBarButtonItem(customView: dividerContainerView)

        toolbarItems.append(fixedSpace)
        toolbarItems.append(dividerItem)
        toolbarItems.append(textItem)

        _toolbar.barTintColor = UIColor.white
//        toolbar.isHidden = true
        toolbar.items = toolbarItems
    }

    private enum ParagraphMenuSelectedItemType {
        case paragraph
        case h1
        case h2
        case code
        case quote
        case bullet
        case numbered
    }

    private var paragraphMenuSelectedItem: ParagraphMenuSelectedItemType = .paragraph

    private func updateToolbar() {
        if let selection = try? getSelection() as? RangeSelection {
            guard let anchorNode = try? selection.anchor.getNode() else { return }

            var element =
                isRootNode(node: anchorNode)
                    ? anchorNode
                    : findMatchingParent(startingNode: anchorNode, findFn: { e in
                        let parent = e.getParent()
                        return parent != nil && isRootNode(node: parent)
                    })

            if element == nil {
                element = anchorNode.getTopLevelElementOrThrow()
            }

            // derive paragraph style
            if let heading = element as? HeadingNode {
                if heading.getTag() == .h1 {
                    paragraphButton?.image = UIImage(named: "h1")
                    paragraphMenuSelectedItem = .h1
                } else {
                    paragraphButton?.image = UIImage(named: "h2")
                    paragraphMenuSelectedItem = .h2
                }
            } else if element is CodeNode {
                paragraphButton?.image = UIImage(systemName: "chevron.left.forwardslash.chevron.right")
                paragraphMenuSelectedItem = .code
            } else if element is QuoteNode {
                paragraphButton?.image = UIImage(systemName: "quote.opening")
                paragraphMenuSelectedItem = .quote
            } else if let element = element as? ListNode {
                var listType: ListType = .bullet
                if let parentList: ListNode = getNearestNodeOfType(node: anchorNode, type: .list) {
                    listType = parentList.getListType()
                } else {
                    listType = element.getListType()
                }
                switch listType {
                case .bullet:
                    paragraphButton?.image = UIImage(systemName: "list.bullet")
                    paragraphMenuSelectedItem = .bullet
                case .number:
                    paragraphButton?.image = UIImage(systemName: "list.number")
                    paragraphMenuSelectedItem = .numbered
                case .check:
                    paragraphButton?.image = UIImage(systemName: "checklist")
                }
            } else {
                paragraphButton?.image = UIImage(systemName: "paragraph")
                paragraphMenuSelectedItem = .paragraph
            }

            paragraphButton?.menu = paragraphMenu
            stylingButton?.menu = stylingMenu

            // Update links
            do {
                let selectedNode = try getSelectedNode(selection: selection)
                let selectedNodeParent = selectedNode.getParent()
                if selectedNode is LinkNode || selectedNodeParent is LinkNode {
                    linkButton?.isSelected = true
                } else {
                    linkButton?.isSelected = false
                }
            } catch {
                print("Error getting the selected Node: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Paragraph Styles

    private var paragraphMenuItems: [UIAction] {
        return [
            UIAction(title: "Normal", image: UIImage(systemName: "paragraph"), state: paragraphMenuSelectedItem == .paragraph ? .on : .off, handler: { [weak self] _ in
                self?.setBlock {
                    createParagraphNode()
                }
            }),
            UIAction(title: "Heading 1", image: UIImage(named: "h1"), state: paragraphMenuSelectedItem == .h1 ? .on : .off, handler: { [weak self] _ in
                self?.setBlock {
                    createHeadingNode(headingTag: .h1)
                }
            }),
            UIAction(title: "Heading 2", image: UIImage(named: "h2"), state: paragraphMenuSelectedItem == .h2 ? .on : .off, handler: { [weak self] _ in
                self?.setBlock {
                    createHeadingNode(headingTag: .h2)
                }
            }),
            UIAction(title: "Code Block", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right"), state: paragraphMenuSelectedItem == .code ? .on : .off, handler: { [weak self] _ in
                self?.setBlock {
                    createCodeNode()
                }
            }),
            UIAction(title: "Quote", image: UIImage(systemName: "quote.opening"), state: paragraphMenuSelectedItem == .quote ? .on : .off, handler: { [weak self] _ in
                self?.setBlock {
                    createQuoteNode()
                }
            }),
            UIAction(title: "Bulleted List", image: UIImage(systemName: "list.bullet"), state: paragraphMenuSelectedItem == .bullet ? .on : .off, handler: { [weak self] _ in
                self?.editor?.dispatchCommand(type: .insertUnorderedList)
            }),
            UIAction(title: "Numbered List", image: UIImage(systemName: "list.number"), state: paragraphMenuSelectedItem == .numbered ? .on : .off, handler: { [weak self] _ in
                self?.editor?.dispatchCommand(type: .insertOrderedList)
            }),
        ]
    }

    private var imageMenuItems: [UIAction] {
        return [
            UIAction(title: "Insert Sample Image", image: UIImage(systemName: "photo"), handler: { [weak self] _ in
                self?.insertSampleImage()
            }),
            UIAction(title: "Insert Selectable Image", image: UIImage(systemName: "photo"), handler: { [weak self] _ in
                self?.insertSelectableImage()
            }),
        ]
    }

    private var stylingMenuItems: [UIAction] {
        var rangeSelection: RangeSelection?
        try? editor?.read {
            if let selection = try? getSelection() as? RangeSelection {
                rangeSelection = selection
            }
        }
        return [
            UIAction(title: "Bold", image: UIImage(systemName: "bold"), state: rangeSelection?.hasFormat(type: .bold) ?? false ? .on : .off, handler: { [weak self] _ in
                self?.toggleBold()
            }),
            UIAction(title: "Italic", image: UIImage(systemName: "italic"), state: rangeSelection?.hasFormat(type: .italic) ?? false ? .on : .off, handler: { [weak self] _ in
                self?.toggleItalic()
            }),
            UIAction(title: "Underline", image: UIImage(systemName: "underline"), state: rangeSelection?.hasFormat(type: .underline) ?? false ? .on : .off, handler: { [weak self] _ in
                self?.toggleUnderline()
            }),
            UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough"), state: rangeSelection?.hasFormat(type: .strikethrough) ?? false ? .on : .off, handler: { [weak self] _ in
                self?.toggleStrikethrough()
            }),
            UIAction(title: "Inline Code", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right"), state: rangeSelection?.hasFormat(type: .code) ?? false ? .on : .off, handler: { [weak self] _ in
                self?.toggleInlineCode()
            }),
        ]
    }

    private func setBlock(creationFunc: () -> ElementNode) {
        try? editor?.update {
            if let selection = try getSelection() as? RangeSelection {
                setBlocksType(selection: selection, createElement: creationFunc)
            }
        }
    }

    private var paragraphMenu: UIMenu {
        return UIMenu(title: "Paragraph Style", image: nil, identifier: nil, options: [], children: paragraphMenuItems)
    }

    private var imageMenu: UIMenu {
        return UIMenu(title: "Insert Image", image: nil, identifier: nil, options: [], children: imageMenuItems)
    }

    private var stylingMenu: UIMenu {
        return UIMenu(title: "Text Style", image: nil, identifier: nil, options: [], children: stylingMenuItems)
    }

    // MARK: - Button actions

    @objc func createHeading1Node(_: UIBarButtonItem) {
        setBlock {
            paragraphMenuSelectedItem == .h1 ? createParagraphNode() : createHeadingNode(headingTag: .h1)
            // Return nothing
        }
    }

    @objc func createHeading2Node(_: UIBarButtonItem) {
        setBlock {
            paragraphMenuSelectedItem == .h2 ? createParagraphNode() : createHeadingNode(headingTag: .h2)
            // Return nothing
        }
    }

    @objc func createQuoteNodeWrap(_: UIBarButtonItem) {
        setBlock {
            createQuoteNode()
            // Return nothing
        }
    }

    @objc private func toggleBold() {
        editor?.dispatchCommand(type: .formatText, payload: TextFormatType.bold)
    }

    @objc private func toggleItalic() {
        editor?.dispatchCommand(type: .formatText, payload: TextFormatType.italic)
    }

    @objc private func toggleUnderline() {
        editor?.dispatchCommand(type: .formatText, payload: TextFormatType.underline)
    }

    @objc private func toggleStrikethrough() {
        editor?.dispatchCommand(type: .formatText, payload: TextFormatType.strikethrough)
    }

    @objc private func toggleInlineCode() {
        editor?.dispatchCommand(type: .formatText, payload: TextFormatType.code)
    }

    @objc private func link() {
        showLinkEditor()
    }

    @objc private func increaseIndent() {
        editor?.dispatchCommand(type: .indentContent, payload: nil)
    }

    @objc private func decreaseIndent() {
        editor?.dispatchCommand(type: .outdentContent, payload: nil)
    }

    private func insertSampleImage() {
        guard let url = Bundle.main.url(forResource: "lexical-logo", withExtension: "png") else {
            return
        }
        try? editor?.update {
            let imageNode = ImageNode(url: url.absoluteString, size: CGSize(width: 300, height: 300), sourceID: "")
            if let selection = try getSelection() {
                _ = try selection.insertNodes(nodes: [imageNode], selectStart: false)
            }
        }
    }

    private func insertSelectableImage() {
        guard let url = Bundle.main.url(forResource: "lexical-logo", withExtension: "png") else {
            return
        }
        try? editor?.update {
            let imageNode = SelectableImageNode(url: url.absoluteString, size: CGSize(width: 300, height: 300), sourceID: "")
            if let selection = try getSelection() {
                _ = try selection.insertNodes(nodes: [imageNode], selectStart: false)
            }
        }
    }

    // MARK: - Link handling

    func showLinkEditor() {
        guard let editor else { return }
        do {
            try editor.read {
                guard let selection = try getSelection() as? RangeSelection else { return }

                let node = try getSelectedNode(selection: selection)
                if let node = node as? LinkNode {
                    _ = showLinkActionSheet(url: node.getURL(), selection: selection)
                } else if let parent = node.getParent() as? LinkNode {
                    _ = showLinkActionSheet(url: parent.getURL(), selection: selection)
                } else {
                    let urlString = "https://"
                    showAlert(url: urlString, isEdit: false)
                }
            }
        } catch {
            print("Error getting the selected node: \(error.localizedDescription)")
        }
    }

    func getSelectedNode(selection: RangeSelection) throws -> Node {
        let anchor = selection.anchor
        let focus = selection.focus

        let anchorNode = try selection.anchor.getNode()
        let focusNode = try selection.focus.getNode()

        if anchorNode == focusNode {
            return anchorNode
        }

        let isBackward = try selection.isBackward()
        if isBackward {
            return try focus.isAtNodeEnd() ? anchorNode : focusNode
        } else {
            return try anchor.isAtNodeEnd() ? focusNode : anchorNode
        }
    }

    func showAlert(url: String?, isEdit: Bool, selection: RangeSelection? = nil) {
        guard let url, let editor else { return }

        var originalSelection: RangeSelection?

        do {
            try editor.read {
                originalSelection = try getSelection() as? RangeSelection
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }

        let title = isEdit ? "Edit Link" : "Link"
        let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let doneAction = UIAlertAction(title: "Done", style: .default) { [weak self, weak alertController] _ in
            guard let strongSelf = self else { return }

            if let textField = alertController?.textFields?.first, let originalSelection {
                let updateSelection = isEdit ? selection : originalSelection
                strongSelf.editor?.dispatchCommand(type: .link, payload: LinkPayload(urlString: textField.text ?? "", originalSelection: updateSelection))
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alertController.addTextField { textField in
            textField.layer.cornerRadius = 20
            textField.text = url
        }

        alertController.addAction(doneAction)
        alertController.addAction(cancelAction)

//    viewControllerForPresentation?.present(alertController, animated: true)
    }

    public func showLinkActionSheet(url: String, selection: RangeSelection?) -> Bool {
        let actionSheet = UIAlertController(title: "Link Action", message: nil, preferredStyle: .actionSheet)

        let removeLinkAction = UIAlertAction(title: "Remove Link", style: .default) { [weak self] _ in
            guard let strongSelf = self else { return }

            strongSelf.editor?.dispatchCommand(type: .link, payload: LinkPayload(urlString: nil, originalSelection: selection))
        }

        let visitLinkAction = UIAlertAction(title: "Visit Link", style: .default) { [weak self] _ in
            guard let strongSelf = self else { return }
            guard let url = URL(string: url) else { return }

            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                let title = "Error"
                let message = "Invalid URL"
                let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
                let okButton = UIAlertAction(title: "OK", style: .cancel)
                alertController.addAction(okButton)

//        strongSelf.viewControllerForPresentation?.present(alertController, animated: true)
            }
        }

        let editLinkAction = UIAlertAction(title: "Edit Link", style: .default) { [weak self] _ in
            guard let strongSelf = self else { return }
            guard let url = URL(string: url) else { return }

            strongSelf.showAlert(url: url.absoluteString, isEdit: true, selection: selection)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        actionSheet.addAction(removeLinkAction)
        actionSheet.addAction(visitLinkAction)
        actionSheet.addAction(editLinkAction)
        actionSheet.addAction(cancelAction)

//    viewControllerForPresentation?.present(actionSheet, animated: true)

        return false
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}