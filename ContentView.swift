import SwiftUI

struct ContentView: View {
    @ObservedObject private var speechRecognizer = SpeechRecognizer()
    @State private var selectedLanguage = "ja-JP" //デフォルトの言語コード

    let languages = ["ja-JP", "en-US", "fr-FR", "es-ES"] //使用する言語コードをここに追加

    var body: some View {
        VStack {
            //言語選択のプルダウン
            Picker("言語を選択", selection: $selectedLanguage) {
                ForEach(languages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .pickerStyle(SegmentedPickerStyle()) //スタイルは自由に変更可能
            .padding()

            //確定されたテキストを表示
            TextEditor(text: $speechRecognizer.finalizedText)
                .frame(height: 200)
                .border(Color.gray, width: 1)
                .padding()

            //リアルタイムの認識テキストを表示
            if !speechRecognizer.recognizedText.isEmpty {
                Text(speechRecognizer.recognizedText)
                    .padding()
                    .foregroundColor(.gray)
            }

            Button(action: {
                if speechRecognizer.isRecording {
                    speechRecognizer.stopRecording()
                } else {
                    //選択された言語コードで録音を開始
                    speechRecognizer.startRecording(language: selectedLanguage)
                }
            }) {
                Text(speechRecognizer.isRecording ? "音声入力を停止" : "音声入力を開始")
                    .padding()
                    .background(speechRecognizer.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
