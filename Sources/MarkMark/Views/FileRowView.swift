import SwiftUI
import MarkdownReaderKit

/// 目录树中单个文件/目录行视图
struct FileRowView: View {
    let node: FileNode
    let fileTreeViewModel: FileTreeViewModel
    let documentViewModel: DocumentViewModel
    @Environment(\.themeColors) private var themeColors

    /// 当前文件是否有未保存的修改
    private var isDirty: Bool {
        !node.isDirectory && documentViewModel.isFileDirty(at: node.path)
    }

    var body: some View {
        HStack(spacing: 6) {
            if node.isDirectory {
                Image(systemName: "folder.fill")
                    .foregroundStyle(themeColors.ink)
                    .frame(width: 16)
            } else {
                Image(systemName: node.isMarkdown ? "doc.text" : "doc")
                    .foregroundStyle(node.isMarkdown ? themeColors.fgSecondary : themeColors.fgMuted)
                    .frame(width: 16)
            }

            Text(node.name)
                .foregroundStyle(node.isMarkdown || node.isDirectory ? themeColors.ink : themeColors.fgSecondary)
                .lineLimit(1)

            if isDirty {
                Text("*")
                    .foregroundStyle(themeColors.accent)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .padding(.trailing, 6)
    }
}
