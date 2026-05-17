import SwiftUI
import AudioEngine

struct ComparePlayerView: View {
    @ObservedObject var viewModel: RestorationViewModel
    @State private var isFrequencyDomain = false
    
    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isPlayerPreparing {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Pre-scanning audio integrated loudness...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(RestorationTheme.subtleText)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .glassCard()
            } else {
                VStack(spacing: 14) {
                    // Header Status
                    HStack {
                        Text("A/B COMPARISON PLAYER")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(RestorationTheme.saffron)
                        
                        Spacer()
                        
                        // Domain Toggle Button
                        Button(action: { isFrequencyDomain.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isFrequencyDomain ? "waveform" : "chart.bar.xaxis")
                                    .font(.system(size: 10))
                                Text(isFrequencyDomain ? "TIME VIEW" : "SPECTRUM VIEW")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(RestorationTheme.subtleText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer().frame(width: 16)
                        
                        if let origLUFS = viewModel.originalLUFSVal, let restLUFS = viewModel.restoredLUFSVal {
                            let delta = restLUFS - origLUFS
                            Text(String(format: "Matched Gain: %.1f dB", delta))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(viewModel.playerVolumeMatchActive ? RestorationTheme.neonTeal : RestorationTheme.subtleText)
                        }
                    }
                    
                    if isFrequencyDomain {
                        SpectrumVisualizerView(
                            spectrum: viewModel.playerSpectrum,
                            color: viewModel.playerOriginalActive ? Color.gray : (viewModel.selectedPreset == .streaming ? RestorationTheme.neonTeal : RestorationTheme.saffron)
                        )
                    } else {
                        // Stacked Dual-Waveform Display
                        StackedWaveformView(
                            originalAmplitudes: viewModel.originalAmplitudes,
                            restoredAmplitudes: viewModel.restoredAmplitudes,
                            progress: viewModel.playerProgress,
                            isOriginalActive: viewModel.playerOriginalActive,
                            restoredColor: viewModel.selectedPreset == .streaming ? RestorationTheme.neonTeal : RestorationTheme.saffron,
                            onSeek: { percent in
                                viewModel.seekPlayer(toPercent: percent)
                            }
                        )
                    }
                    
                    // Time Counter labels
                    HStack {
                        Text(formatTime(viewModel.playerCurrentTime))
                        Spacer()
                        Text(formatTime(viewModel.playerTotalDuration))
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RestorationTheme.subtleText)
                    .padding(.top, -4)
                    
                    // Player Controls Row
                    HStack(spacing: 20) {
                        // Play / Pause Button
                        Button(action: { viewModel.togglePlayback() }) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.playerOriginalActive ? Color.gray.opacity(0.2) : RestorationTheme.saffron.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Circle()
                                            .stroke(viewModel.playerOriginalActive ? Color.gray.opacity(0.4) : RestorationTheme.saffron.opacity(0.4), lineWidth: 1.5)
                                    )
                                
                                Image(systemName: viewModel.playerIsPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(viewModel.playerOriginalActive ? .white : RestorationTheme.saffron)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Switch Target Button (Original vs Restored)
                        Button(action: { viewModel.toggleSource() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left.and.right.circle.fill")
                                    .font(.system(size: 14))
                                Text(viewModel.playerOriginalActive ? "ORIGINAL DEGRADED" : "RESTORED PREVIEW")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(viewModel.playerOriginalActive ? Color.gray.opacity(0.3) : RestorationTheme.saffron.opacity(0.8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Volume Match Toggle Button
                        Button(action: { viewModel.toggleVolumeMatch() }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.playerVolumeMatchActive ? "speaker.wave.3.fill" : "speaker.wave.3")
                                Text("VOLUME MATCH")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(viewModel.playerVolumeMatchActive ? RestorationTheme.neonTeal : RestorationTheme.subtleText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(viewModel.playerVolumeMatchActive ? RestorationTheme.neonTeal.opacity(0.1) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(viewModel.playerVolumeMatchActive ? RestorationTheme.neonTeal.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Continuous Looping Toggle Button
                        Button(action: { viewModel.toggleLoop() }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.playerLoopActive ? "repeat.1" : "repeat")
                                Text("LOOP")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(viewModel.playerLoopActive ? RestorationTheme.saffron : RestorationTheme.subtleText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(viewModel.playerLoopActive ? RestorationTheme.saffron.opacity(0.1) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(viewModel.playerLoopActive ? RestorationTheme.saffron.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 180)
                .glassCard()
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN, !seconds.isInfinite else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
