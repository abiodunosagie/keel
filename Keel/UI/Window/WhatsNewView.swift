import SwiftUI

struct WhatsNewView: View {
  let close: () -> Void

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("What's New in Keel \(version)")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Theme.ink)
      ForEach(ReleaseNotes.notes(for: version) ?? []) { item in
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: item.symbol)
            .font(.system(size: 20))
            .foregroundStyle(Theme.accent)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(item.detail).font(.system(size: 12)).foregroundStyle(Theme.ink2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      Spacer()
      HStack {
        Spacer()
        Button("Continue", action: close).keyboardShortcut(.defaultAction)
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.surface)
  }
}
