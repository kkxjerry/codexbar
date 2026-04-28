import SwiftUI

struct RelayProfileRowView: View {
    let profile: RelayProfile
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: profile.isActive ? "key.fill" : "network")
                    .font(.system(size: 10))
                    .foregroundColor(profile.isActive ? .accentColor : .secondary)

                Text(profile.rowTitle)
                    .font(.system(size: 12, weight: profile.isActive ? .semibold : .regular))
                    .foregroundColor(profile.isActive ? .accentColor : .primary)
                    .lineLimit(1)

                if !profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(profile.model)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                }

                if profile.isActive {
                    Text(L.relayActiveTag)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(3)
                }

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)

                if !profile.isActive {
                    Button(L.relayActivateButton, action: onActivate)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .font(.system(size: 10, weight: .medium))
                }
            }

            Text("\(profile.hostLabel) · \(profile.maskedAPIKey)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(profile.isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if profile.isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
    }
}
