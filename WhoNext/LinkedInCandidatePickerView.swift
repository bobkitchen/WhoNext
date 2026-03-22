import SwiftUI

struct LinkedInCandidatePickerView: View {
    let candidates: [LinkedInCandidate]
    let personName: String
    let onSelect: (LinkedInCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Select LinkedIn Profile")
                    .font(.system(size: 16, weight: .semibold))
                Text("Multiple profiles found for \"\(personName)\". Select the correct one.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Candidate list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(candidates) { candidate in
                        Button(action: { onSelect(candidate) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)

                                if !candidate.headline.isEmpty {
                                    Text(candidate.headline)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Text(candidate.url)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.blue.opacity(0.7))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)

            Divider()

            // Footer
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 420)
    }
}
