import AVFoundation
import CloudKit
import Combine
import WatchKit

// MARK: - Voice Manager
class VoiceManager: NSObject, ObservableObject {
    static let shared = VoiceManager()
    
    // MARK: - Configuration
    private enum Config {
        static let maxDuration: TimeInterval = 5.0
        static let sampleRate: Double = 22050
        static let subscriptionID = "VoiceMessage-Sub"
    }
    
    // MARK: - Properties
    private let container = CKContainer(identifier: "iCloud.com.adilemre.selfprod")
    private lazy var database = container.publicCloudDatabase
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var tempFileURL: URL?
    
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingProgress: Double = 0
    @Published var hasIncomingMessage = false
    @Published var incomingMessageID: CKRecord.ID?
    @Published var incomingMessageDuration: Double = 0
    @Published var subscribed = false
    @Published var errorMessage: String?
    @Published var showSentMessage = false
    
    // Safe recordID storage (instead of objc_setAssociatedObject)
    private var currentPlaybackRecordID: CKRecord.ID?
    
    // MARK: - Init
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Audio Session
    private func setupAudioSession() {
        // Skip in Preview mode to prevent crash
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("Audio session setup failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Recording
    func startRecording() {
        guard !isRecording else { return }
        
        // Request microphone permission
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if granted {
                    self.beginRecording()
                } else {
                    self.errorMessage = "Mikrofon izni gerekli"
                }
            }
        }
    }
    
    private func beginRecording() {
        let fileName = UUID().uuidString + ".m4a"
        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent(fileName)
        
        guard let url = tempFileURL else { return }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: Config.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record(forDuration: Config.maxDuration)
            
            isRecording = true
            recordingProgress = 0
            
            // Progress timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self, self.isRecording else {
                    timer.invalidate()
                    return
                }
                
                let progress = (self.audioRecorder?.currentTime ?? 0) / Config.maxDuration
                DispatchQueue.main.async {
                    self.recordingProgress = min(progress, 1.0)
                }
                
                if progress >= 1.0 {
                    timer.invalidate()
                    self.stopRecording()
                }
            }
            
            // Haptic feedback
            WKInterfaceDevice.current().play(.start)
            
        } catch {
            #if DEBUG
            print("Recording failed: \(error.localizedDescription)")
            #endif
            errorMessage = "Kayıt başlatılamadı"
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        isRecording = false
        
        WKInterfaceDevice.current().play(.stop)
        
        // Send if we have a recording
        if let url = tempFileURL, FileManager.default.fileExists(atPath: url.path) {
            sendVoiceMessage(from: url)
        }
    }
    
    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        isRecording = false
        recordingProgress = 0
        
        // Delete temp file
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURL = nil
    }
    
    // MARK: - Send Voice Message
    private func sendVoiceMessage(from url: URL) {
        guard let myID = CloudKitManager.shared.currentUserID,
              let partnerID = CloudKitManager.shared.partnerID else {
            errorMessage = "Eşleşme yok"
            return
        }
        
        let record = CKRecord(recordType: "VoiceMessage")
        record["fromID"] = myID
        record["toID"] = partnerID
        record["timestamp"] = Date()
        record["duration"] = audioRecorder?.currentTime ?? 0
        record["audio"] = CKAsset(fileURL: url)
        
        database.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    #if DEBUG
                    print("Voice message send failed: \(error.localizedDescription)")
                    #endif
                    self?.errorMessage = "Gönderilemedi"
                } else {
                    #if DEBUG
                    print("Voice message sent!")
                    #endif
                    WKInterfaceDevice.current().play(.success)
                    
                    // Show sent message
                    self?.showSentMessage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.showSentMessage = false
                    }
                    
                    // Cleanup temp file
                    try? FileManager.default.removeItem(at: url)
                    self?.tempFileURL = nil
                }
            }
        }
    }
    
    // MARK: - Subscribe
    func subscribeToVoiceMessages() {
        guard !subscribed else { return }
        guard let myID = CloudKitManager.shared.currentUserID else { return }
        
        let predicate = NSPredicate(format: "toID == %@", myID)
        let subscription = CKQuerySubscription(
            recordType: "VoiceMessage",
            predicate: predicate,
            subscriptionID: Config.subscriptionID,
            options: [.firesOnRecordCreation]
        )
        
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "Aşkımdan bir sesli mesaj 🎤"
        info.soundName = "default"
        info.shouldBadge = true
        info.category = "VoiceMessage"
        subscription.notificationInfo = info
        
        database.save(subscription) { [weak self] _, error in
            if let error = error as? CKError {
                let desc = error.localizedDescription.lowercased()
                if desc.contains("exists") || desc.contains("duplicate") || desc.contains("already") {
                    self?.subscribed = true
                }
            } else {
                self?.subscribed = true
                #if DEBUG
                print("Subscribed to voice messages")
                #endif
            }
        }
    }
    
    // MARK: - Check for Incoming Messages
    func checkForIncomingMessages() {
        guard let myID = CloudKitManager.shared.currentUserID else { return }
        
        let predicate = NSPredicate(format: "toID == %@", myID)
        let query = CKQuery(recordType: "VoiceMessage", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1) { [weak self] result in
            switch result {
            case .success(let (results, _)):
                DispatchQueue.main.async {
                    if let match = results.first,
                       let record = try? match.1.get() {
                        self?.hasIncomingMessage = true
                        self?.incomingMessageID = record.recordID
                        self?.incomingMessageDuration = record["duration"] as? Double ?? 0
                    } else {
                        self?.hasIncomingMessage = false
                        self?.incomingMessageID = nil
                        self?.incomingMessageDuration = 0
                    }
                }
            case .failure:
                break
            }
        }
    }
    
    // MARK: - Play & Delete
    func playIncomingMessage() {
        // Prevent concurrent playback
        guard !isPlaying else { return }
        guard let recordID = incomingMessageID else { return }
        
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self,
                  let record = record,
                  let asset = record["audio"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                return
            }
            
            DispatchQueue.main.async {
                self.playAudio(from: fileURL, recordID: recordID)
            }
        }
    }
    
    private func playAudio(from url: URL, recordID: CKRecord.ID) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            
            // Store recordID safely (instead of objc_setAssociatedObject)
            currentPlaybackRecordID = recordID
            
            WKInterfaceDevice.current().play(.notification)
            
        } catch {
            #if DEBUG
            print("Playback failed: \(error.localizedDescription)")
            #endif
            errorMessage = "Çalınamadı"
        }
    }
    
    private func deleteMessage(recordID: CKRecord.ID) {
        database.delete(withRecordID: recordID) { [weak self] _, error in
            DispatchQueue.main.async {
                if error == nil {
                    #if DEBUG
                    print("Voice message deleted after playback")
                    #endif
                    self?.hasIncomingMessage = false
                    self?.incomingMessageID = nil
                    self?.incomingMessageDuration = 0
                    
                    // Check if there are more messages
                    self?.checkForIncomingMessages()
                }
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension VoiceManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingProgress = 0
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension VoiceManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            
            // Delete message after playing using stored recordID
            if let recordID = self.currentPlaybackRecordID {
                self.currentPlaybackRecordID = nil
                self.deleteMessage(recordID: recordID)
            }
        }
    }
}
