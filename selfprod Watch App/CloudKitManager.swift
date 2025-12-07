import CloudKit
import Combine

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container = CKContainer(identifier: "iCloud.com.adilemre.selfprod")
    private lazy var database = container.publicCloudDatabase
    private let pairingTTL: TimeInterval = 10 * 60 // 10 minutes
    private let heartbeatQueueKey = "PendingHeartbeats"
    private var lastPairingRecordID: CKRecord.ID?
    private let lastSentKey = "LastHeartbeatSentAt"
    private let lastReceivedKey = "LastHeartbeatReceivedAt"
    
    @Published var currentUserID: String?
    @Published var partnerID: String? {
        didSet {
            if let id = partnerID {
                UserDefaults.standard.set(id, forKey: "partnerID")
            } else {
                UserDefaults.standard.removeObject(forKey: "partnerID")
            }
        }
    }
    @Published var isPaired: Bool = false
    @Published var errorMessage: String?
    @Published var permissionStatus: CKAccountStatus = .couldNotDetermine
    @Published var pendingHeartbeats: [HeartbeatDraft] = [] {
        didSet { persistPendingHeartbeats() }
    }
    @Published var lastSentAt: Date? {
        didSet { persistDate(lastSentAt, key: lastSentKey) }
    }
    @Published var lastReceivedAt: Date? {
        didSet { persistDate(lastReceivedAt, key: lastReceivedKey) }
    }
    @Published var pushRegistered: Bool = false
    @Published var heartbeatSubscribed: Bool = false
    @Published var pairingSubscribed: Bool = false
    @Published var healthChecks: [HealthCheck] = []
    
    private init() {
        self.partnerID = UserDefaults.standard.string(forKey: "partnerID")
        self.isPaired = self.partnerID != nil
        self.pendingHeartbeats = Self.loadPendingHeartbeats(from: heartbeatQueueKey)
        self.lastSentAt = UserDefaults.standard.object(forKey: lastSentKey) as? Date
        self.lastReceivedAt = UserDefaults.standard.object(forKey: lastReceivedKey) as? Date
        
        checkAccountStatus()
    }
    
    private static func loadPendingHeartbeats(from key: String) -> [HeartbeatDraft] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([HeartbeatDraft].self, from: data)) ?? []
    }
    
    private func persistPendingHeartbeats() {
        if let data = try? JSONEncoder().encode(pendingHeartbeats) {
            UserDefaults.standard.set(data, forKey: heartbeatQueueKey)
        }
    }
    
    private func persistDate(_ date: Date?, key: String) {
        if let date = date {
            UserDefaults.standard.set(date, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    struct HeartbeatDraft: Codable, Identifiable {
        let id: UUID
        let toID: String
        let timestamp: Date
    }
    
    struct HealthCheck: Identifiable {
        let id = UUID()
        let title: String
        let isOK: Bool
        let detail: String
    }
    
    func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.permissionStatus = status
                switch status {
                case .available:
                    self?.errorMessage = nil
                    self?.getCurrentUserID()
                case .noAccount:
                    self?.errorMessage = "Lütfen iCloud hesabınıza giriş yapın."
                case .restricted:
                    self?.errorMessage = "iCloud erişimi kısıtlanmış."
                case .couldNotDetermine:
                     if let error = error {
                        self?.errorMessage = "Hata: \(error.localizedDescription)"
                     } else {
                        self?.errorMessage = "iCloud durumu belirlenemedi."
                     }
                @unknown default:
                    self?.errorMessage = "Bilinmeyen iCloud durumu."
                }
            }
        }
    }
    
    func getCurrentUserID() {
        container.fetchUserRecordID { [weak self] recordID, error in
            if let id = recordID?.recordName {
                DispatchQueue.main.async {
                    self?.currentUserID = id
                    print("User ID found: \(id)")
                    
                    if self?.isPaired == true {
                        self?.subscribeToHeartbeats()
                        self?.flushPendingHeartbeats()
                    }
                }
            } else if let error = error {
                DispatchQueue.main.async {
                    print("Error getting user ID: \(error.localizedDescription)")
                    self?.errorMessage = "Kullanıcı kimliği alınamadı: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Pairing
    
    func generatePairingCode(completion: @escaping (String?) -> Void) {
        guard let myID = currentUserID else { completion(nil); return }
        
        // Prevent concurrent requests
        guard permissionStatus == .available || permissionStatus == .couldNotDetermine else {
            DispatchQueue.main.async {
                self.errorMessage = "iCloud kullanılamıyor, lütfen tekrar deneyin."
            }
            completion(nil)
            return
        }
        
        // 1. Invalidate (Delete) old sessions first
        invalidatePreviousSessions { [weak self] in
            guard let self = self else { return }
            
            // 2. Generate new code
            let code = String(Int.random(in: 100000...999999))
            let record = CKRecord(recordType: "PairingSession")
            record["code"] = code
            record["initiatorID"] = myID
            record["expiresAt"] = Date().addingTimeInterval(self.pairingTTL)
            record["used"] = false
            
            self.database.save(record) { savedRecord, error in
                if error == nil {
                    print("Pairing code generated: \(code)")
                    DispatchQueue.main.async {
                        if let rID = savedRecord?.recordID {
                            self.lastPairingRecordID = rID
                            self.subscribeToPairingUpdate(recordID: rID)
                        }
                        self.errorMessage = nil
                    }
                    completion(code)
                } else {
                    DispatchQueue.main.async {
                        print("Error generating code: \(error?.localizedDescription ?? "")")
                        self.errorMessage = "Kod oluşturulamadı: \(error?.localizedDescription ?? "Bilinmeyen Hata")"
                    }
                    completion(nil)
                }
            }
        }
    }
    
    private func invalidatePreviousSessions(completion: @escaping () -> Void) {
        guard let myID = currentUserID else { completion(); return }
        
        let predicate = NSPredicate(format: "initiatorID == %@", myID)
        let query = CKQuery(recordType: "PairingSession", predicate: predicate)
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 10) { [weak self] result in
            switch result {
            case .success(let (results, _)):
                let recordsToDelete = results.compactMap { try? $0.1.get().recordID }
                
                if recordsToDelete.isEmpty {
                    completion()
                    return
                }
                
                let modifyOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordsToDelete)
                modifyOp.modifyRecordsResultBlock = { _ in
                    // We don't strictly care if delete fails or succeeds, just proceed
                    print("Invalidated \(recordsToDelete.count) old sessions.")
                    completion()
                }
                self?.database.add(modifyOp)
                
            case .failure(let error):
                print("Failed to fetch old sessions for invalidation: \(error.localizedDescription)")
                // Proceed anyway, not blocking
                completion()
            }
        }
    }
    
    func enterPairingCode(_ code: String, completion: @escaping (Bool) -> Void) {
        let predicate = NSPredicate(format: "code == %@", code)
        let query = CKQuery(recordType: "PairingSession", predicate: predicate)
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1) { [weak self] result in
            switch result {
            case .success(let (results, _)):
                guard let match = results.first else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Kod bulunamadı veya süresi doldu."
                    }
                    completion(false)
                    return
                }
                
                guard let self = self,
                      let record = try? match.1.get(),
                      let myID = self.currentUserID else {
                    completion(false)
                    return
                }
                
                if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                    DispatchQueue.main.async {
                        self.errorMessage = "Kodun süresi dolmuş. Yeniden oluştur."
                    }
                    completion(false)
                    return
                }
                
                if (record["used"] as? Bool) == true || record["receiverID"] != nil {
                    DispatchQueue.main.async {
                        self.errorMessage = "Bu kod zaten kullanılmış."
                    }
                    completion(false)
                    return
                }
                
                // Found session, update with my ID
                record["receiverID"] = myID
                record["used"] = true
                
                let modifyOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                modifyOp.savePolicy = .changedKeys
                modifyOp.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        // Success, I am paired to the initiator
                        if let initiatorID = record["initiatorID"] as? String {
                            DispatchQueue.main.async {
                                self.partnerID = initiatorID
                                self.isPaired = true
                                self.subscribeToHeartbeats()
                                self.flushPendingHeartbeats()
                                completion(true)
                            }
                        } else {
                            completion(false)
                        }
                    case .failure(let error):
                        print("Modified failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.errorMessage = "Bağlanılamadı: \(error.localizedDescription)"
                        }
                        completion(false)
                    }
                }
                self.database.add(modifyOp)
                
            case .failure(let error):
                print("Fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.errorMessage = "Kod okunamadı: \(error.localizedDescription)"
                }
                completion(false)
            }
        }
    }
    
    private func subscribeToPairingUpdate(recordID: CKRecord.ID) {
        let subscriptionID = "Pairing-\(recordID.recordName)"
        let subscription = CKQuerySubscription(recordType: "PairingSession", predicate: NSPredicate(format: "recordID == %@", recordID), subscriptionID: subscriptionID, options: [.firesOnRecordUpdate])
        
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.category = "Pairing"
        subscription.notificationInfo = info
        
        database.save(subscription) { _, error in
            if let error = error as? CKError {
                if self.shouldTreatSubscriptionAsSuccess(error) {
                    DispatchQueue.main.async {
                        self.pairingSubscribed = true
                        self.errorMessage = nil
                    }
                } else {
                    print("Subscription failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Eşleşme bildirimi abonesi kurulamadı. Tekrar deneyin."
                        self.pairingSubscribed = false
                    }
                }
            } else {
                print("Listening for pairing completion...")
                DispatchQueue.main.async {
                    self.pairingSubscribed = true
                }
            }
        }
    }
    
    func checkPairingStatus(recordID: CKRecord.ID) {
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            if let record = record, let receiverID = record["receiverID"] as? String {
                DispatchQueue.main.async {
                    self?.lastPairingRecordID = recordID
                }
                
                if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Eşleşme süresi doldu, yeni kod oluştur."
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self?.partnerID = receiverID
                    self?.isPaired = true
                    self?.subscribeToHeartbeats()
                    self?.flushPendingHeartbeats()
                }
            }
        }
    }
    
    // MARK: - Heartbeat
    
    func sendHeartbeat() {
        guard let myID = currentUserID, let pID = partnerID else {
            DispatchQueue.main.async {
                self.errorMessage = "Eşleşme yok. Önce bağlanın."
            }
            return
        }
        
        let timestamp = Date()
        
        guard permissionStatus == .available else {
            queueHeartbeat(toID: pID, timestamp: timestamp)
            DispatchQueue.main.async {
                self.errorMessage = "iCloud çevrimdışı. Kalp sıraya alındı."
            }
            return
        }
        
        let record = CKRecord(recordType: "Heartbeat")
        record["fromID"] = myID
        record["toID"] = pID
        record["timestamp"] = timestamp
        
        database.save(record) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                print("Failed to send heartbeat: \(error.localizedDescription)")
                if self.isNetworkRelated(error) {
                    self.queueHeartbeat(toID: pID, timestamp: timestamp)
                    DispatchQueue.main.async {
                        self.errorMessage = "Bağlantı yokken kalp sıraya alındı."
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Gönderilemedi: \(error.localizedDescription)"
                    }
                }
            } else {
                print("Heartbeat sent!")
                self.flushPendingHeartbeats()
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.lastSentAt = timestamp
                }
            }
        }
    }
    
    // MARK: - Self test
    func runSelfTest() {
        var results: [HealthCheck] = []
        
        let iCloudOK = permissionStatus == .available
        results.append(HealthCheck(title: "iCloud Durumu", isOK: iCloudOK, detail: iCloudOK ? "Uygun" : "Kısıtlı veya hesap yok"))
        
        let pushOK = pushRegistered
        results.append(HealthCheck(title: "Push Kaydı", isOK: pushOK, detail: pushOK ? "Kayıtlı" : "Kayıt yok"))
        
        results.append(HealthCheck(title: "Kalp Aboneliği", isOK: heartbeatSubscribed, detail: heartbeatSubscribed ? "Aktif" : "Yenilemeniz gerekebilir"))
        results.append(HealthCheck(title: "Eşleşme Aboneliği", isOK: pairingSubscribed || lastPairingRecordID == nil, detail: pairingSubscribed ? "Aktif" : "Gerekirse yeniden kurun"))
        
        let hasPartner = partnerID != nil
        results.append(HealthCheck(title: "Eşleşme", isOK: hasPartner, detail: hasPartner ? "Partner bağlı" : "Partner yok"))
        
        results.append(HealthCheck(title: "Bekleyen Kalpler", isOK: pendingHeartbeats.isEmpty, detail: pendingHeartbeats.isEmpty ? "Kuyruk boş" : "\(pendingHeartbeats.count) bekliyor"))
        
        DispatchQueue.main.async {
            self.healthChecks = results
        }
    }

    
    func subscribeToHeartbeats() {
        guard let myID = currentUserID else { return }
        
        // Subscribe to Heartbeats where toID == myID
        let subscriptionID = "Heartbeat-Sub"
        let predicate = NSPredicate(format: "toID == %@", myID)
        let subscription = CKQuerySubscription(recordType: "Heartbeat", predicate: predicate, subscriptionID: subscriptionID, options: [.firesOnRecordCreation])
        
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "Seni özledimmm 🧡"
        info.soundName = "default"
        info.shouldBadge = true
        info.category = "Heartbeat"
        subscription.notificationInfo = info
        
        database.save(subscription) { _, error in
            if let error = error as? CKError {
                print("Heartbeat subscription result: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    if self.shouldTreatSubscriptionAsSuccess(error) {
                        self.errorMessage = nil
                        self.heartbeatSubscribed = true
                    } else {
                        // Show detailed error for debugging
                        self.errorMessage = "Bildirim hatası: \(error.localizedDescription)"
                        self.heartbeatSubscribed = false
                    }
                }
            } else {
                print("Subscribed to heartbeats.")
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.heartbeatSubscribed = true
                }
            }
        }
    }
    
    func refreshSubscriptions() {
        subscribeToHeartbeats()
        if let recordID = lastPairingRecordID {
            subscribeToPairingUpdate(recordID: recordID)
        }
    }
    
    func refreshPairingStatus() {
        if let recordID = lastPairingRecordID {
            checkPairingStatus(recordID: recordID)
        } else {
            // Check if we have a locally stored partnerID but maybe session is lost
            // For now, mostly used when waiting for code
            if let pID = partnerID {
                 // Already paired locally
                isPaired = true
            }
        }
    }
    
    // MARK: - Offline queue helpers
    
    private func queueHeartbeat(toID: String, timestamp: Date) {
        DispatchQueue.main.async {
            let draft = HeartbeatDraft(id: UUID(), toID: toID, timestamp: timestamp)
            self.pendingHeartbeats.append(draft)
        }
    }
    
    func flushPendingHeartbeats() {
        guard permissionStatus == .available,
              let myID = currentUserID,
              let pID = partnerID,
              !pendingHeartbeats.isEmpty else { return }
        
        let drafts = pendingHeartbeats
        
        for draft in drafts {
            let record = CKRecord(recordType: "Heartbeat")
            record["fromID"] = myID
            record["toID"] = pID
            record["timestamp"] = draft.timestamp
            
            database.save(record) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error {
                        print("Failed to flush heartbeat: \(error.localizedDescription)")
                        self.errorMessage = "Bekleyen kalp gönderilemedi: \(error.localizedDescription)"
                    } else {
                        self.pendingHeartbeats.removeAll { $0.id == draft.id }
                        if self.pendingHeartbeats.isEmpty {
                            self.errorMessage = nil
                        }
                        self.lastSentAt = draft.timestamp
                    }
                }
            }
        }
    }
    
    private func isNetworkRelated(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }
    
    private func shouldTreatSubscriptionAsSuccess(_ error: CKError) -> Bool {
        // When a subscription with the same ID already exists CloudKit can return a variety of codes.
        let description = error.localizedDescription.lowercased()
        if error.code == .serverRejectedRequest {
            return description.contains("exists") || description.contains("already") || description.contains("duplicate")
        }
        return description.contains("already exists") || description.contains("duplicate subscription")
    }
    
    // MARK: - Push registration feedback
    
    func pushRegistrationFailed(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.pushRegistered = false
        }
    }
    
    func retryIdentityFetch() {
        guard permissionStatus == .available else {
            DispatchQueue.main.async {
                self.errorMessage = "iCloud kullanılamıyor. Ayarları kontrol edin."
            }
            return
        }
        getCurrentUserID()
    }
    
    func unpair() {
        let cleanup = {
            DispatchQueue.main.async {
                self.partnerID = nil
                self.isPaired = false
                self.lastPairingRecordID = nil
                self.pendingHeartbeats.removeAll()
                self.lastSentAt = nil
                self.lastReceivedAt = nil
                self.errorMessage = nil
            }
        }
        
        // Clean up any sessions we initiated; ignore errors because partner may own the record.
        invalidatePreviousSessions {
            cleanup()
        }
    }
    
    func markHeartbeatReceived(at date: Date = Date()) {
        DispatchQueue.main.async {
            self.lastReceivedAt = date
        }
    }
}
