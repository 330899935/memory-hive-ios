import Foundation
import AVFoundation
import Combine

/// 录音器：一个按钮切换「开始/停止」，停止后返回临时文件 URL 交给 ThoughtStore 归队
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var tempURL: URL?

    /// 切换录制状态
    func toggle() {
        if isRecording {
            _ = stop()
        } else {
            start()
        }
    }

    /// 开始录音（失败静默，不崩溃）
    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.record()
            tempURL = url
            recorder = rec
            isRecording = true
        } catch {
            print("录音启动失败：\(error)")
        }
    }

    /// 停止录音，返回临时文件 URL（供归队）；失败返回 nil
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        isRecording = false
        let url = tempURL
        recorder = nil
        tempURL = nil
        return url
    }
}
