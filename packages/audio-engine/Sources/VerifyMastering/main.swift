import Foundation
import AVFoundation
import AudioEngine

// Helper to convert AVAudioPCMBuffer to [[Float]] channels-first array
func bufferToChannels(buffer: AVAudioPCMBuffer) -> [[Float]] {
    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)
    var channels: [[Float]] = []
    
    guard let floatPointerArray = buffer.floatChannelData else {
        return []
    }
    
    for c in 0..<channelCount {
        let channelPointer = floatPointerArray[c]
        let channelArray = Array(UnsafeBufferPointer(start: channelPointer, count: frameLength))
        channels.append(channelArray)
    }
    return channels
}

// Helper to convert [[Float]] channels-first array to AVAudioPCMBuffer
func channelsToBuffer(channels: [[Float]], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let channelCount = UInt32(channels.count)
    let frameLength = UInt32(channels[0].count)
    
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
        return nil
    }
    
    buffer.frameLength = frameLength
    
    guard let floatPointerArray = buffer.floatChannelData else {
        return nil
    }
    
    for c in 0..<Int(channelCount) {
        let channelPointer = floatPointerArray[c]
        let channelArray = channels[c]
        channelArray.withUnsafeBufferPointer { srcPtr in
            channelPointer.initialize(from: srcPtr.baseAddress!, count: Int(frameLength))
        }
    }
    
    return buffer
}

// CLI Entry Point
func main() {
    let arguments = CommandLine.arguments
    
    guard arguments.count >= 3 else {
        print("Sangeet AI - Mastering Verification CLI Tool")
        print("Usage: swift run verify-mastering <input-file> <preset: streaming | remaster> [output-file]")
        exit(1)
    }
    
    let inputPath = arguments[1]
    let presetString = arguments[2].lowercased()
    let outputPath = arguments.count >= 4 ? arguments[3] : nil
    
    let preset: MasteringChain.Preset
    if presetString == "streaming" {
        preset = .streaming
    } else if presetString == "remaster" {
        preset = .remaster
    } else {
        print("Error: Invalid preset '\(presetString)'. Use 'streaming' or 'remaster'.")
        exit(1)
    }
    
    let inputURL = URL(fileURLWithPath: inputPath)
    
    print("[verify-mastering] Loading input audio file: \(inputURL.lastPathComponent)...")
    
    let decoder = AudioDecoder()
    let buffer: AVAudioPCMBuffer
    do {
        buffer = try decoder.decode(fileURL: inputURL)
    } catch {
        print("Error: Failed to decode input file: \(error.localizedDescription)")
        exit(1)
    }
    
    let channels = bufferToChannels(buffer: buffer)
    guard !channels.isEmpty else {
        print("Error: No channels extracted from buffer.")
        exit(1)
    }
    
    let sampleRate = buffer.format.sampleRate
    let channelCount = buffer.format.channelCount
    let duration = Double(buffer.frameLength) / sampleRate
    
    print("[verify-mastering] Properties: \(channelCount) channels, \(sampleRate) Hz, \(String(format: "%.2f", duration)) seconds")
    
    if abs(sampleRate - 48000.0) > 1.0 {
        print("Warning: Mastering chain is optimized for 48 kHz. Input sample rate is \(sampleRate) Hz.")
    }
    
    // 1. Measure initial metrics
    let lufsMeter = LUFSMeter()
    let tpDetector = TruePeakDetector()
    
    let initialLUFS = lufsMeter.analyzeLoudness(channels: channels)
    let initialTP = tpDetector.detectPeakdBTP(channels: channels)
    
    print("[verify-mastering] Processing mastering chain with preset: \(presetString)...")
    
    // 2. Process mastering chain
    let chain = MasteringChain()
    let masteredChannels = chain.process(channels: channels, preset: preset)
    
    // 3. Measure final metrics
    let finalLUFS = lufsMeter.analyzeLoudness(channels: masteredChannels)
    let finalTP = tpDetector.detectPeakdBTP(channels: masteredChannels)
    
    // 4. Print results
    print("\n--- Mastering Verification Results ---")
    print(String(format: "| Metric     | Before           | After            | Target           | Status |"))
    print("|------------|------------------|------------------|------------------|--------|")
    
    let targetLUFS = preset.targetLoudnessLUFS
    let lufsStatus = abs(finalLUFS - targetLUFS) <= 1.5 ? "PASS" : "FAIL"
    let tpStatus = finalTP <= -0.98 ? "PASS" : "FAIL"
    
    print(String(format: "| Loudness   | %6.2f LUFS      | %6.2f LUFS      | %6.2f LUFS      |  %@  |", initialLUFS, finalLUFS, targetLUFS, lufsStatus))
    print(String(format: "| True Peak  | %6.2f dBTP      | %6.2f dBTP      | <= -1.00 dBTP    |  %@  |", initialTP, finalTP, tpStatus))
    print("--------------------------------------\n")
    
    // 5. Write to target file if provided
    if let outPath = outputPath {
        let outURL = URL(fileURLWithPath: outPath)
        print("[verify-mastering] Writing mastered audio to: \(outURL.lastPathComponent)...")
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            print("Error: Could not create output AVAudioFormat.")
            exit(1)
        }
        
        guard let outputBuffer = channelsToBuffer(channels: masteredChannels, format: outputFormat) else {
            print("Error: Could not convert channels to output buffer.")
            exit(1)
        }
        
        let encoder = AudioEncoder()
        do {
            try encoder.encode(buffer: outputBuffer, to: outURL)
            print("[verify-mastering] Successfully wrote \(outURL.lastPathComponent).")
        } catch {
            print("Error: Failed to encode and write output file: \(error.localizedDescription)")
            exit(1)
        }
    }
}

main()
