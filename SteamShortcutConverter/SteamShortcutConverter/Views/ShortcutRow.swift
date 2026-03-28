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
    let displayName: String
    let hasCustomName: Bool
    let onRename: (String) -> Void
    let onResetName: () -> Void
    
    @State private var isEditing = false
    @State private var editedName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
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
                if isEditing {
                    HStack(spacing: 8) {
                        TextField("Name", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                saveEdit()
                            }
                        
                        Button("Save") {
                            saveEdit()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("Cancel") {
                            cancelEdit()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.body)
                            .lineLimit(1)
                        
                        if hasCustomName {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .help("Custom name")
                        }
                        
                        // Rename button next to name
                        Menu {
                            Button("Rename") {
                                startEdit()
                            }
                            
                            if hasCustomName {
                                Button("Reset to Original") {
                                    onResetName()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 16, height: 16)
                        .opacity(0.4)
                        .help("Rename shortcut")
                    }
                }
                
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
        .cornerRadius(6)
    }
    
    private func startEdit() {
        editedName = displayName
        isEditing = true
        isTextFieldFocused = true
    }
    
    private func saveEdit() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            onRename(trimmedName)
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
        editedName = ""
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
