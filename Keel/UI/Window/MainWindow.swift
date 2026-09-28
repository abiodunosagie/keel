import SwiftUI

// The dashboard and settings window from the mockup: a sidebar of sections and one pane.
struct MainWindow: View {
  static let id = "main"

  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      List(AppSection.allCases, selection: $model.section) { section in
        Label(section.title, systemImage: section.symbol)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(180)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          pane(for: model.section)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Theme.surface)
      .navigationTitle(model.section.title)
    }
    .frame(minWidth: 780, idealWidth: 780, minHeight: 560, idealHeight: 600)
  }

  @ViewBuilder
  private func pane(for section: AppSection) -> some View {
    switch section {
    case .dashboard: DashboardPane()
    case .history: HistoryPane()
    case .charge: ChargePane()
    case .schedule: SchedulePane()
    case .automation: AutomationPane()
    case .calibration: CalibrationPane()
    case .appearance: AppearancePane()
    case .general: GeneralPane()
    }
  }
}

// A pane heading and one-line explanation, as in the mockup. Literal text is looked up in the
// string catalog; text built at runtime arrives already translated.
struct PaneHeader: View {
  let title: Text
  let lede: Text

  init(title: LocalizedStringKey, lede: LocalizedStringKey) {
    self.title = Text(title)
    self.lede = Text(lede)
  }

  @_disfavoredOverload
  init(title: LocalizedStringKey, lede: String) {
    self.title = Text(title)
    self.lede = Text(verbatim: lede)
  }

  @_disfavoredOverload
  init(title: String, lede: String) {
    self.title = Text(verbatim: title)
    self.lede = Text(verbatim: lede)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      title
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(Theme.ink)
      lede
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.bottom, 2)
  }
}

// A group of rows in a bordered panel.
struct RowGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { subviews in
        ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
          if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
          subview
        }
      }
    }
    .panel(radius: 10)
  }
}

// One setting: title and explanation on the left, the control on the right. Literal text is
// looked up in the string catalog; text built at runtime arrives already translated.
struct SettingRow<Control: View>: View {
  let title: Text
  let detail: Text?
  let control: Control

  init(title: LocalizedStringKey, detail: LocalizedStringKey?, @ViewBuilder control: () -> Control) {
    self.title = Text(title)
    self.detail = detail.map { Text($0) }
    self.control = control()
  }

  @_disfavoredOverload
  init(title: String, detail: String?, @ViewBuilder control: () -> Control) {
    self.title = Text(verbatim: title)
    self.detail = detail.map { Text(verbatim: $0) }
    self.control = control()
  }

  @_disfavoredOverload
  init(title: LocalizedStringKey, detail: String?, @ViewBuilder control: () -> Control) {
    self.title = Text(title)
    self.detail = detail.map { Text(verbatim: $0) }
    self.control = control()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        title.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
        if let detail {
          detail
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      control
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }
}

// A small monospaced value chip, like the mockup's fields.
struct ValueChip: View {
  let text: String

  var body: some View {
    Text(text)
      .font(Theme.mono(12))
      .foregroundStyle(Theme.ink)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Theme.chip, in: RoundedRectangle(cornerRadius: 6))
  }
}
