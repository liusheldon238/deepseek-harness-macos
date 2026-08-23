public enum DesktopEditCommand: String, CaseIterable, Sendable {
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll

    public var title: String {
        switch self {
        case .undo: "撤销"
        case .redo: "重做"
        case .cut: "剪切"
        case .copy: "复制"
        case .paste: "粘贴"
        case .selectAll: "全选"
        }
    }

    public var keyEquivalent: String {
        switch self {
        case .undo: "z"
        case .redo: "Z"
        case .cut: "x"
        case .copy: "c"
        case .paste: "v"
        case .selectAll: "a"
        }
    }
}
