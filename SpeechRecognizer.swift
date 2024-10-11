import Foundation
import Speech
import AVFoundation

class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = ""  //リアルタイムの認識テキスト
    @Published var finalizedText = ""   //確定したテキスト
    @Published var isRecording = false  //録音中かどうか

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private let silenceDuration: TimeInterval = 1.3  //無音とみなす時間（秒）

    init(language: String = "ja-JP") {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
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
    func startRecording(language: String = "ja-JP") {
        if isRecording {
            return
        }

        //指定された言語で音声認識を再設定
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        
        //以前のタスクがあればキャンセル
        recognitionTask?.cancel()
        recognitionTask = nil

        //オーディオセッションの設定
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

        inputNode.removeTap(onBus: 0)  //既存のタップを削除
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

        //音声認識タスクの開始
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                //無音タイマーをリセット
                self.resetSilenceTimer()

                if result.isFinal {
                    //最終結果が得られた場合
                    self.finalizedText += result.bestTranscription.formattedString + " "
                    self.recognizedText = ""  //認識中のテキストをクリア
                    print("最終結果: \(result.bestTranscription.formattedString)")
                } else {
                    //部分的な結果を表示
                    self.recognizedText = result.bestTranscription.formattedString
                    print("部分結果: \(result.bestTranscription.formattedString)")
                }
            }

            if error != nil {
                //エラーが発生した場合
                self.stopRecording()
            }
        }
    }

    //録音を停止
    func stopRecording() {
        if !isRecording {
            return
        }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false

        //無音タイマーを無効化
        silenceTimer?.invalidate()
        silenceTimer = nil

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
        if isRecording {
            print("無音が検知されました")

            //現在のタスクをキャンセル
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest?.endAudio()
            recognitionRequest = nil

            //オーディオエンジンを一時停止
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)

            //認識中のテキストを確定テキストに追加
            DispatchQueue.main.async {
                if !self.recognizedText.isEmpty {
                    self.finalizedText += self.recognizedText + " "
                    self.recognizedText = ""
                }
            }

            //録音を再開
            self.startRecording(language: Locale.current.identifier)
        }
    }
}
