import SwiftUI

struct DictateMenuView: View {
    @ObservedObject var viewModel: DictateViewModel

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                Text(viewModel.loadingStatus)
                    .font(.caption)
            } else if !viewModel.modelLoaded {
                Button("Load Models") {
                    Task { await viewModel.loadModels() }
                }
            } else {
                Button {
                    viewModel.toggleRecording()
                } label: {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .foregroundStyle(viewModel.isRecording ? .red : .accentColor)
                        Text(viewModel.isRecording ? "Stop Dictation" : "Start Dictation")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if viewModel.isRecording {
                    Text(viewModel.isSpeechActive ? "Speech detected" : "Listening...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // Always reserve the transcript area so the MenuBarExtra
                // popover is sized correctly when it first opens. Otherwise
                // the popover snapshots its content size at open time and
                // doesn't resize when sentences/partialText grow later,
                // clipping new content off the visible area.
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.sentences.isEmpty && viewModel.partialText.isEmpty {
                            Text(viewModel.isRecording ? "Speak..." : "Click Start to dictate")
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(viewModel.sentences.enumerated()), id: \.offset) { _, sentence in
                                Text(sentence)
                                    .font(.system(.body, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !viewModel.partialText.isEmpty {
                                Text(viewModel.partialText)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 320, height: 220)

                HStack {
                    Button("Copy") { viewModel.copyToClipboard() }
                        .disabled(viewModel.sentences.isEmpty && viewModel.partialText.isEmpty)
                    Spacer()
                    Button("Clear") { viewModel.clearText() }
                        .disabled(viewModel.sentences.isEmpty && viewModel.partialText.isEmpty)
                }
                .padding(.horizontal)
            }

            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }

            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 280)
    }
}
