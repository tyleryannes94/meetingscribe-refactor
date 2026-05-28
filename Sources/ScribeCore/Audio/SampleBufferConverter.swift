import Foundation
import AVFoundation
import CoreMedia

enum SampleBufferConverter {
    /// Converts a CMSampleBuffer carrying audio (e.g. from ScreenCaptureKit) into
    /// an AVAudioPCMBuffer with the same format as the input.
    /// Returns nil if the conversion fails or the buffer has no audio data.
    static func toPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return nil
        }
        pcm.frameLength = AVAudioFrameCount(numSamples)

        var blockBuffer: CMBlockBuffer?
        let ablSize = MemoryLayout<AudioBufferList>.size +
            (Int(format.channelCount) - 1) * MemoryLayout<AudioBuffer>.size
        let ablPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSize,
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ablPtr.deallocate() }
        let ablBound = ablPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablBound,
            bufferListSize: ablSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let srcABL = UnsafeMutableAudioBufferListPointer(ablBound)
        let dstABL = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        guard srcABL.count == dstABL.count else { return nil }
        for i in 0..<srcABL.count {
            let src = srcABL[i]
            var dst = dstABL[i]
            let bytes = min(Int(src.mDataByteSize), Int(dst.mDataByteSize))
            if let s = src.mData, let d = dst.mData, bytes > 0 {
                memcpy(d, s, bytes)
            }
            dst.mDataByteSize = src.mDataByteSize
            dstABL[i] = dst
        }
        return pcm
    }
}
