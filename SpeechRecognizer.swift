import Foundation
import Speech
import AVFoundation

class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = ""  //リアルタイムの認識テキスト
    @Published var finalizedText = ""   //確定したテキスト
    @Published var isRecording = false  //録音中かどうか
    private var isStopping = false      //停止中かどうかを管理

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private let silenceDuration: TimeInterval = 1.3  //無音とみなす時間（秒）

    private var selectedLanguage: String = "ja-JP" //現在選択されている言語を保持

    init(language: String = "ja-JP") {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        self.selectedLanguage = language
        requestAuthorization()
    }

    //音声認識の許可をリクエスト
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("音声認識が許可されました")
                case .denied:
                    print("音声認識が拒否されました")
                case .restricted:
                    print("音声認識が制限されています")
                case .notDetermined:
                    print("音声認識がまだ認証されていません")
                @unknown default:
                    fatalError("未知の認証ステータス")
                }
            }
        }
    }

    //録音を開始（言語を引数として指定可能）
    func startRecording(language: String) {
        if isRecording || isStopping {
            return
        }

        self.selectedLanguage = language
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("オーディオセッションの設定エラー: \(error.localizedDescription)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("リクエストの作成に失敗しました")
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            (buffer, when) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("オーディオエンジンの開始エラー: \(error.localizedDescription)")
        }

        isRecording = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.resetSilenceTimer()

                if result.isFinal {
                    self.finalizedText += result.bestTranscription.formattedString + " "
                    self.recognizedText = ""
                } else {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }

            if error != nil {
                self.stopRecording()
            }
        }
    }

    //録音を停止
    func stopRecording() {
        if !isRecording || isStopping {
            return
        }

        isStopping = true
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
        isStopping = false  //停止が完了したのでフラグをリセット

        print("ユーザーによって録音が停止されました")
    }

    //無音タイマーをリセット
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { _ in
            self.handleSilence()
        }
    }

    //無音が検知されたときの処理
    private func handleSilence() {
        if isRecording && !isStopping {
            print("無音が検知されました")

            //現在のタスクをキャンセル
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest?.endAudio()
            recognitionRequest = nil

            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)

            DispatchQueue.main.async {
                if !self.recognizedText.isEmpty {
                    self.finalizedText += self.recognizedText + " "
                    self.recognizedText = ""
                    print("ここで確定したよ！")
                }

                //停止状態を監視
                self.monitorStopState {
                    print("この後に録音再開するよ")
                    self.startRecording(language: self.selectedLanguage)
                }
            }
        }
    }

    //停止状態を監視して、停止が完了したら再開
    private func monitorStopState(completion: @escaping () -> Void) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !self.isStopping {  //停止が完了したかチェック
                timer.invalidate()  //タイマーを停止
                completion()         //再開処理を実行
            }
        }
    }
}
