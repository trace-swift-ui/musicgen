
import SwiftUI
import Foundation
import Combine
import AVFoundation

struct ContentView: View {
    @State private var isLoading: Bool = false
    @State private var audioPlayer: AVPlayer?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var pollingTimer: Timer?
    @State private var inputText: String = ""
    @FocusState private var isInputFieldFocused: Bool
    @State private var albumArt: Image?

    var body: some View {
        VStack {
            Spacer()
            if let audioPlayer = audioPlayer, audioPlayer.timeControlStatus != .paused {
                ZStack {
                    if let albumArt = albumArt {
                        albumArt
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 350, height: 350)
                            .clipped()
                    }
                    MusicPlayerControls(audioPlayer: $audioPlayer)
                }
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Text("Enter prompt to generate music")
            }
            Spacer()
            inputField
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear {
            loadAlbumArt()
        }
    }
    
    var inputField: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Enter prompt", text: $inputText)
                    .focused($isInputFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button(action: {
                    fetchPrediction(prompt: inputText)
                    isInputFieldFocused = false
                }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
            .padding(.bottom, isInputFieldFocused ? 320 : 0)
        }
    }
    
    func loadAlbumArt() {
        ImageLoader.loadImage(from: "https://source.unsplash.com/random/album") { image in
            self.albumArt = image
        }
    }
    
    func fetchPrediction(prompt: String) {
        isLoading = true
        let url = URL(string: "https://api.replicate.com/v1/predictions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Token REPLICATE_API_KEY", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "version": "b05b1dff1d8c6dc63d14b0cdb42135378dcb87f6373b0d3d341ede46e59e2b38",
            "input": [
                
                "top_k": 250,
                "top_p": 0,
                "prompt": prompt,
                "duration": 5,
                "temperature": 1,
                "continuation": false,
                "model_version": "stereo-large",
                "output_format": "wav",
                "continuation_start": 0,
                "multi_band_diffusion": false,
                "normalization_strategy": "peak",
                "classifier_free_guidance": 3
            ]
        ]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.httpBody = jsonData
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: PredictionResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    print(error.localizedDescription)
                    self.isLoading = false
                }
            }, receiveValue: { response in
                self.startPolling(predictionId: response.id)
            })
            .store(in: &cancellables)
    }
    
    func startPolling(predictionId: String) {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            pollPredictionStatus(predictionId: predictionId)
        }
    }
    
    func pollPredictionStatus(predictionId: String) {
        let url = URL(string: "https://api.replicate.com/v1/predictions/\(predictionId)")!
        var request = URLRequest(url: url)
        request.addValue("Token REPLICATE_API_KEY", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: PredictionStatusResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    print(error.localizedDescription)
                    self.isLoading = false
                }
            }, receiveValue: { response in
                if response.status == "succeeded", let urlString = response.output, let url = URL(string: urlString) {
                    self.playAudio(from: url)
                    self.pollingTimer?.invalidate()
                    self.pollingTimer = nil
                    self.isLoading = false
                }
            })
            .store(in: &cancellables)
    }
    
    func playAudio(from url: URL) {
        let playerItem = AVPlayerItem(url: url)
        self.audioPlayer = AVPlayer(playerItem: playerItem)
        self.audioPlayer?.play()
        
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { _ in
                self.audioPlayer?.seek(to: .zero)
                self.audioPlayer?.play()
            }
            .store(in: &cancellables)
    }
}

struct MusicPlayerControls: View {
    @Binding var audioPlayer: AVPlayer?
    
    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                audioPlayer?.play()
            }) {
                Image(systemName: "pause.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.primary)
            }
            Spacer()
        }
    }
}

struct ImageLoader {
    static func loadImage(from urlString: String, completion: @escaping (Image?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, let uiImage = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let image = Image(uiImage: uiImage)
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
}

struct PredictionResponse: Codable {
    let id: String
}

struct PredictionStatusResponse: Codable {
    let status: String
    let output: String?
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
