import Foundation
import AVFoundation

public final class SynchronizedAudioPlayer {
    private let engine = AVAudioEngine()
    private let originalPlayer = AVAudioPlayerNode()
    private let restoredPlayer = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    
    private var originalFile: AVAudioFile?
    private var restoredFile: AVAudioFile?
    
    public private(set) var isPlaying = false
    public private(set) var isOriginalActive = false
    public private(set) var isVolumeMatchEnabled = false
    
    public private(set) var originalLUFS: Double = -14.0
    public private(set) var restoredLUFS: Double = -14.0
    private var originalGainMultiplier: Float = 1.0
    
    // Timer / display link coordinator
    private var timeUpdateTimer: Timer?
    public var onTimeUpdate: ((Double, Double) -> Void)? // currentTime, totalDuration
    
    private let fftAnalyzer = RealtimeFFTAnalyzer()
    public var onSpectrumUpdate: (([Float]) -> Void)?
    
    public init() {
        engine.attach(originalPlayer)
        engine.attach(restoredPlayer)
        engine.attach(mixer)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.connect(originalPlayer, to: mixer, format: format)
        engine.connect(restoredPlayer, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self, self.isPlaying else { return }
            guard let floatData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength >= 1024 {
                let samples = Array(UnsafeBufferPointer(start: floatData[0], count: 1024))
                let spectrum = self.fftAnalyzer.analyze(samples: samples, sampleRate: buffer.format.sampleRate)
                self.onSpectrumUpdate?(spectrum)
            }
        }
    }
    
    deinit {
        stop()
        mixer.removeTap(onBus: 0)
        engine.stop()
    }
    
    /// Prepares the player with original and restored audio files, scanning the original LUFS for precise volume matching.
    /// - Parameters:
    ///   - originalURL: URL of the original audio file.
    ///   - restoredURL: URL of the restored audio file.
    ///   - restoredLUFS: Pre-measured integrated LUFS of the restored file.
    public func prepare(originalURL: URL, restoredURL: URL, restoredLUFS: Double) async throws {
        stop()
        
        // 1. Load AVAudioFiles
        let originalAccess = originalURL.startAccessingSecurityScopedResource()
        let restoredAccess = restoredURL.startAccessingSecurityScopedResource()
        
        defer {
            if originalAccess { originalURL.stopAccessingSecurityScopedResource() }
            if restoredAccess { restoredURL.stopAccessingSecurityScopedResource() }
        }
        
        let origFile = try AVAudioFile(forReading: originalURL)
        let restFile = try AVAudioFile(forReading: restoredURL)
        
        self.originalFile = origFile
        self.restoredFile = restFile
        self.restoredLUFS = restoredLUFS
        
        // 2. Perform integrated LUFS scan on the original file asynchronously
        let origLUFS = try await Task.detached(priority: .userInitiated) {
            let meter = LUFSMeter()
            let channels = try Self.readAllFloatChannels(from: originalURL)
            return meter.analyzeLoudness(channels: channels)
        }.value
        
        self.originalLUFS = origLUFS
        
        // 3. Compute volume matching gain multiplier
        // Apply gain to the quieter one to match within 0.1 LU.
        let lufsDelta = restoredLUFS - origLUFS
        if abs(lufsDelta) > 0.1 {
            // If original is quieter, apply positive gain to original, or vice versa
            self.originalGainMultiplier = pow(10.0, Float(lufsDelta) / 20.0)
        } else {
            self.originalGainMultiplier = 1.0
        }
        
        // 4. Reset initial active volumes
        if isOriginalActive {
            originalPlayer.volume = isVolumeMatchEnabled ? originalGainMultiplier : 1.0
            restoredPlayer.volume = 0.0
        } else {
            originalPlayer.volume = 0.0
            restoredPlayer.volume = 1.0
        }
        
        // 5. Start engine if not already running
        if !engine.isRunning {
            try engine.start()
        }
        
        // 6. Schedule initial playback from start
        schedule(fromFrame: 0)
    }
    
    private func schedule(fromFrame frameOffset: AVAudioFramePosition) {
        guard let origFile = originalFile, let restFile = restoredFile else { return }
        
        originalPlayer.stop()
        restoredPlayer.stop()
        
        let fileLength = origFile.length
        guard frameOffset < fileLength else { return }
        
        let framesToPlay = AVAudioFrameCount(fileLength - frameOffset)
        
        originalPlayer.scheduleSegment(origFile, startingFrame: frameOffset, frameCount: framesToPlay, at: nil, completionHandler: nil)
        restoredPlayer.scheduleSegment(restFile, startingFrame: frameOffset, frameCount: framesToPlay, at: nil, completionHandler: nil)
    }
    
    /// Starts sample-accurate synchronized playback for both nodes.
    public func play() {
        guard originalFile != nil, restoredFile != nil else { return }
        guard !isPlaying else { return }
        
        // Sample-accurate future synchronization start
        let sampleRate = originalFile!.processingFormat.sampleRate
        let delayOffset = 0.05 // 50ms scheduling buffer
        
        let lastRenderTime = engine.outputNode.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
        let startSampleTime = lastRenderTime.sampleTime + Int64(delayOffset * sampleRate)
        let startAVTime = AVAudioTime(sampleTime: startSampleTime, atRate: sampleRate)
        
        originalPlayer.play(at: startAVTime)
        restoredPlayer.play(at: startAVTime)
        
        isPlaying = true
        startTimeUpdateTimer()
    }
    
    /// Pauses playback on both nodes.
    public func pause() {
        guard isPlaying else { return }
        originalPlayer.pause()
        restoredPlayer.pause()
        isPlaying = false
        stopTimeUpdateTimer()
        onSpectrumUpdate?(Array(repeating: 0.0, count: 30))
    }
    
    /// Stops playback and resets playhead.
    public func stop() {
        originalPlayer.stop()
        restoredPlayer.stop()
        isPlaying = false
        stopTimeUpdateTimer()
        schedule(fromFrame: 0)
        onSpectrumUpdate?(Array(repeating: 0.0, count: 30))
    }
    
    /// Toggles active playback track using a click-free 30ms programmatic crossfade.
    public func setOriginalActive(_ active: Bool) {
        guard isOriginalActive != active else { return }
        isOriginalActive = active
        
        let steps = 10
        let crossfadeDuration = 0.030 // 30ms crossfade
        let stepInterval = crossfadeDuration / Double(steps)
        
        let origTargetVolume: Float = active ? (isVolumeMatchEnabled ? originalGainMultiplier : 1.0) : 0.0
        let restTargetVolume: Float = active ? 0.0 : 1.0
        
        let origStartVolume = originalPlayer.volume
        let restStartVolume = restoredPlayer.volume
        
        for i in 1...steps {
            let t = Float(i) / Float(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + (stepInterval * Double(i))) {
                self.originalPlayer.volume = origStartVolume + t * (origTargetVolume - origStartVolume)
                self.restoredPlayer.volume = restStartVolume + t * (restTargetVolume - restStartVolume)
            }
        }
    }
    
    /// Toggles volume matching between files.
    public func setVolumeMatchEnabled(_ enabled: Bool) {
        guard isVolumeMatchEnabled != enabled else { return }
        isVolumeMatchEnabled = enabled
        
        // Immediately apply new volumes based on active track
        if isOriginalActive {
            originalPlayer.volume = enabled ? originalGainMultiplier : 1.0
            restoredPlayer.volume = 0.0
        } else {
            originalPlayer.volume = 0.0
            restoredPlayer.volume = 1.0
        }
    }
    
    /// Seeks playback to a specific percentage.
    public func seek(toPercent percent: Double) {
        guard let origFile = originalFile else { return }
        
        let targetFrame = AVAudioFramePosition(percent * Double(origFile.length))
        
        let wasPlaying = isPlaying
        if wasPlaying {
            pause()
        }
        
        schedule(fromFrame: targetFrame)
        
        if wasPlaying {
            play()
        } else {
            // Trigger callbacks for visual update
            let sampleRate = origFile.processingFormat.sampleRate
            let currentTime = Double(targetFrame) / sampleRate
            let totalDuration = Double(origFile.length) / sampleRate
            onTimeUpdate?(currentTime, totalDuration)
        }
    }
    
    // MARK: - Time Monitoring
    
    private func startTimeUpdateTimer() {
        stopTimeUpdateTimer()
        
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }
    
    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
    
    private func updateTime() {
        guard let origFile = originalFile, let playerTime = originalPlayer.lastRenderTime else { return }
        guard let playerSeconds = originalPlayer.playerTime(forNodeTime: playerTime) else { return }
        
        let sampleRate = origFile.processingFormat.sampleRate
        let totalDuration = Double(origFile.length) / sampleRate
        let currentTime = Double(playerSeconds.sampleTime) / sampleRate
        
        onTimeUpdate?(currentTime, totalDuration)
    }
    
    // MARK: - Helpers
    
    private static func readAllFloatChannels(from fileURL: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard frameCount > 0 else { return [] }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SynchronizedAudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "PCM Buffer alloc failed"])
        }
        
        try file.read(into: buffer)
        
        guard let floatChannelData = buffer.floatChannelData else {
            throw NSError(domain: "SynchronizedAudioPlayer", code: -2, userInfo: [NSLocalizedDescriptionKey: "No float channel data"])
        }
        
        let channelCount = Int(format.channelCount)
        let length = Int(buffer.frameLength)
        
        var channels: [[Float]] = []
        for c in 0..<channelCount {
            let channelPtr = floatChannelData[c]
            let channelArray = Array(UnsafeBufferPointer(start: channelPtr, count: length))
            channels.append(channelArray)
        }
        
        return channels
    }
}
