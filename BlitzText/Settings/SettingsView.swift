import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var modelManager: LocalModelManager
    @State private var selectedTab: Tab = .anpassen

    enum Tab: String, CaseIterable, Identifiable {
        case anpassen, zugang, lokal, sprecher, hotkeys, ueber
        var id: String { rawValue }
        var label: String {
            switch self {
            case .anpassen:  return "Anpassen"
            case .zugang:    return "Zugang"
            case .lokal:     return "Lokales Modell"
            case .sprecher:  return "Sprecher"
            case .hotkeys:   return "Hotkeys"
            case .ueber:     return "Über"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case .anpassen:  AnpassenTab()
                    case .zugang:    ZugangTab()
                    case .lokal:     LokalTab()
                    case .sprecher:  SprecherTab()
                    case .hotkeys:   HotkeysTab()
                    case .ueber:     UeberTab()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, idealWidth: 560, minHeight: 640, idealHeight: 640)
    }
}
