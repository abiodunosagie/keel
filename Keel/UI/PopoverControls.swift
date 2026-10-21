import AppKit
import SwiftUI

// The app's own commands, as menu items: dashboard, settings and a visible Quit.
struct PopoverCommands: View {
  let open: (AppSection) -> Void

  var body: some View {
    VStack(spacing: 0) {
      MenuRow(title: String(localized: "Open Dashboard…")) { open(.dashboard) }
      MenuRow(title: String(localized: "Settings…"), shortcut: "⌘,") { open(.charge) }
        .keyboardShortcut(",", modifiers: .command)
      MenuRow(title: String(localized: "Quit Keel"), shortcut: "⌘Q") { NSApp.terminate(nil) }
        .keyboardShortcut("q", modifiers: .command)
    }
    .padding(.top, 6)
  }
}

private struct MenuRow: View {
  let title: String
  var shortcut: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
        Spacer()
        if let shortcut {
          Text(verbatim: shortcut).foregroundStyle(.tertiary)
        }
      }
    }
    .buttonStyle(HoverRowStyle(verticalPadding: 4))
  }
}

// A full-width row that highlights under the pointer, like a menu item.
struct HoverRowStyle: ButtonStyle {
  var verticalPadding: CGFloat = 6

  func makeBody(configuration: Configuration) -> some View {
    HoverRow(configuration: configuration, verticalPadding: verticalPadding)
  }

  private struct HoverRow: View {
    let configuration: ButtonStyleConfiguration
    let verticalPadding: CGFloat
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.5)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovered && isEnabled ? 0.07 : 0)))
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
  }
}

struct SectionDivider: View {
  var body: some View {
    Divider().padding(.vertical, 2)
  }
}

// Edit mode: every section with show or hide and move up or down.
struct PopoverEditor: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Sections").font(.headline)
        Spacer()
        Button("Done") { model.isEditingPopover = false }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.vertical, 8)
      ForEach(Array(model.popoverLayout.order.enumerated()), id: \.element) { index, card in
        let hidden = model.popoverLayout.hidden.contains(card)
        HStack(spacing: 8) {
          Toggle(card.title, isOn: Binding(
            get: { !hidden },
            set: { _ in model.popoverLayout.toggle(card) }
          ))
          .toggleStyle(.checkbox)
          Spacer()
          Button { model.popoverLayout.move(card, by: -1) } label: {
            Label("Move up", systemImage: "chevron.up").labelStyle(.iconOnly)
          }
          .buttonStyle(IconButtonStyle())
          .disabled(index == 0)
          Button { model.popoverLayout.move(card, by: 1) } label: {
            Label("Move down", systemImage: "chevron.down").labelStyle(.iconOnly)
          }
          .buttonStyle(IconButtonStyle())
          .disabled(index == model.popoverLayout.order.count - 1)
        }
        .padding(.vertical, 3)
      }
      Button("Reset Layout") { model.popoverLayout = PopoverLayout() }
        .padding(.vertical, 8)
    }
  }
}

private struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.secondary)
      .frame(width: 22, height: 22)
      .background(configuration.isPressed ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
      .contentShape(Rectangle())
  }
}
