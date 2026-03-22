//
//  ShortcutRow.swift
//  SteamShortcutConverter
//
//  Row view for displaying a single shortcut in the list
//

import SwiftUI

struct ShortcutRow: View {
    let shortcut: SteamShortcut
    let emulatorType: EmulatorType?
    @Binding var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            
            // Icon preview
            iconView
            
            // Shortcut info
            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut.appName)
                    .font(.body)
                    .lineLimit(1)
                
                if let emulator = emulatorType {
                    Text(emulator.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private var iconView: some View {
        if let iconData = shortcut.icon {
            iconImage(from: iconData)
        } else {
            defaultIcon
        }
    }
    
    @ViewBuilder
    private func iconImage(from iconData: IconData) -> some View {
        switch iconData {
        case .embedded(let data):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
            } else {
                defaultIcon
            }
            
        case .filePath(let path):
            if let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
            } else {
                defaultIcon
            }
        }
    }
    
    private var defaultIcon: some View {
        Image(systemName: "gamecontroller.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .foregroundColor(.secondary)
    }
}
