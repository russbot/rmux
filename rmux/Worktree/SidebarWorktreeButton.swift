import SwiftUI

struct SidebarWorktreeButton: View {
    @EnvironmentObject var tabManager: TabManager
    @State private var showWorktreePicker = false

    var body: some View {
        Button {
            showWorktreePicker = true
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .help(String(localized: "sidebar.worktree.button.help", defaultValue: "New Worktree"))
        .popover(isPresented: $showWorktreePicker) {
            WorktreePickerView()
                .environmentObject(tabManager)
        }
    }
}
