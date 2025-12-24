import CloudKit
import Combine

// MARK: - CloudKit Error Types
enum CloudKitError: LocalizedError {
    case noAccount
    case restricted
    case undetermined
    case networkUnavailable
    case serviceUnavailable
    case rateLimited
    case sendFailed(String)
    case pairingExpired
    case codeNotFound
    case codeAlreadyUsed
    case selfPairing
    case invalidCodeFormat
    case pairingFailed(String)
    case fetchFailed(String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "Lütfen iCloud hesabınıza giriş yapın."
        case .restricted:
            return "iCloud erişimi kısıtlanmış."
        case .undetermined:
            return "iCloud durumu belirlenemedi."
        case .networkUnavailable:
            return "İnternet bağlantınızı kontrol edin."
        case .serviceUnavailable:
            return "iCloud servisi şu an ulaşılamıyor."
        case .rateLimited:
            return "Çok fazla istek. Biraz bekleyin."
        case .sendFailed(let detail):
            return "Gönderilemedi: \(detail)"
        case .pairingExpired:
            return "Kodun süresi dolmuş. Yeniden oluştur."
        case .codeNotFound:
            return "Kod bulunamadı veya süresi doldu."
        case .codeAlreadyUsed:
            return "Bu kod zaten kullanılmış."
        case .selfPairing:
            return "Kendine kalp gönderemezsin. Eşleşmeyi yenile."
        case .invalidCodeFormat:
            return "Geçersiz kod formatı. 6 haneli sayı girin."
        case .pairingFailed(let detail):
            return "Bağlanılamadı: \(detail)"
        case .fetchFailed(let detail):
            return "Kod okunamadı: \(detail)"
        case .unknown:
            return "Bilinmeyen iCloud durumu."
        }
    }
}

// MARK: - CloudKit Manager Protocol
protocol CloudKitManagerProtocol: AnyObject {
    var currentUserID: String? { get }
    var partnerID: String? { get set }
    var isPaired: Bool { get }
    var permissionStatus: CKAccountStatus { get }
    
    func sendHeartbeat(completion: @escaping (Bool) -> Void)
    func generatePairingCode(completion: @escaping (String?) -> Void)
    func enterPairingCode(_ code: String, completion: @escaping (Bool) -> Void)
    func unpair()
}

// MARK: - CloudKit Manager
class CloudKitManager: ObservableObject, CloudKitManagerProtocol {
    static let shared = CloudKitManager()
    
    // MARK: - Constants
    private enum StorageKeys {
        static let partnerID = "partnerID"
        static let lastSentAt = "LastHeartbeatSentAt"
        static let lastReceivedAt = "LastHeartbeatReceivedAt"
    }
    
    private enum SubscriptionIDs {
        static let heartbeat = "Heartbeat-Sub"
        static func pairing(_ recordName: String) -> String {
            "Pairing-\(recordName)"
        }
    }
    
    private enum Config {
        static let pairingTTL: TimeInterval = 10 * 60 // 10 minutes
        static let heartbeatTimeout: TimeInterval = 10.0
        static let heartbeatCooldown: TimeInterval = 2.0
        static let maxRetryAttempts = 2
        static let pairingCodeLength = 6
        static let maxPartnerIDLength = 256
    }
    
    // MARK: - Private Properties
    private let container = CKContainer(identifier: "iCloud.com.adilemre.selfprod")
    private lazy var database = container.publicCloudDatabase
    private var lastPairingRecordID: CKRecord.ID?
    private var accountChangeObserver: NSObjectProtocol?
    private var lastHeartbeatAttempt: Date?
    
    // MARK: - Published Properties
    @Published var currentUserID: String?
    @Published var partnerID: String? {
        didSet {
            guard partnerID != oldValue else { return }
            if let id = partnerID {
                // Validate partner ID format
                guard !id.isEmpty, id.count < Config.maxPartnerIDLength else {
                    partnerID = nil
                    return
                }
                UserDefaults.standard.set(id, forKey: StorageKeys.partnerID)
            } else {
                UserDefaults.standard.removeObject(forKey: StorageKeys.partnerID)
            }
        }
    }
    @Published var isPaired: Bool = false
    @Published var errorMessage: String?
    @Published var permissionStatus: CKAccountStatus = .couldNotDetermine
    @Published var lastSentAt: Date? {
        didSet { persistDate(lastSentAt, key: StorageKeys.lastSentAt) }
    }
    @Published var lastReceivedAt: Date? {
        didSet { persistDate(lastReceivedAt, key: StorageKeys.lastReceivedAt) }
    }
    @Published var pushRegistered: Bool = false
    @Published var heartbeatSubscribed: Bool = false
    @Published var pairingSubscribed: Bool = false
    @Published var healthChecks: [HealthCheck] = []
    @Published var isSendingHeartbeat: Bool = false
    
    // MARK: - Health Check Model
    struct HealthCheck: Identifiable {
        let id = UUID()
        let title: String
        let isOK: Bool
        let detail: String
    }
    
    // MARK: - Initialization
    private init() {
        self.partnerID = UserDefaults.standard.string(forKey: StorageKeys.partnerID)
        self.isPaired = self.partnerID != nil
        self.lastSentAt = UserDefaults.standard.object(forKey: StorageKeys.lastSentAt) as? Date
        self.lastReceivedAt = UserDefaults.standard.object(forKey: StorageKeys.lastReceivedAt) as? Date
        
        setupAccountChangeObserver()
        checkAccountStatus()
    }
    
    deinit {
        if let observer = accountChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Account Change Observer
    private func setupAccountChangeObserver() {
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccountStatus()
        }
    }
    
    // MARK: - Persistence Helpers
    private func persistDate(_ date: Date?, key: String) {
        if let date = date {
            UserDefaults.standard.set(date, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    // MARK: - Account Status
    func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.permissionStatus = status
                switch status {
                case .available:
                    self?.errorMessage = nil
                    self?.getCurrentUserID()
                case .noAccount:
                    self?.setError(.noAccount)
                case .restricted:
                    self?.setError(.restricted)
                case .couldNotDetermine:
                    if let error = error {
                        self?.errorMessage = "Hata: \(error.localizedDescription)"
                    } else {
                        self?.setError(.undetermined)
                    }
                @unknown default:
                    self?.setError(.unknown)
                }
            }
        }
    }
    
    func getCurrentUserID() {
        container.fetchUserRecordID { [weak self] recordID, error in
            if let id = recordID?.recordName {
                DispatchQueue.main.async {
                    self?.currentUserID = id
                    #if DEBUG
                    print("User ID found: \(id)")
                    #endif
                    
                    if self?.isPaired == true {
                        self?.subscribeToHeartbeats()
                    }
                }
            } else if let error = error {
                DispatchQueue.main.async {
                    #if DEBUG
                    print("Error getting user ID: \(error.localizedDescription)")
                    #endif
                    self?.errorMessage = "Kullanıcı kimliği alınamadı: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Error Handling
    private func setError(_ error: CloudKitError) {
        self.errorMessage = error.errorDescription
    }
    
    private func setErrorOnMain(_ error: CloudKitError) {
        DispatchQueue.main.async {
            self.setError(error)
        }
    }
    
    // MARK: - Pairing
    
    func generatePairingCode(completion: @escaping (String?) -> Void) {
        guard let myID = currentUserID else {
            completion(nil)
            return
        }
        
        // Prevent requests when iCloud is not available
        guard permissionStatus == .available || permissionStatus == .couldNotDetermine else {
            setErrorOnMain(.networkUnavailable)
            completion(nil)
            return
        }
        
        // Invalidate old sessions first, then generate new code
        invalidatePreviousSessions { [weak self] in
            guard let self = self else { return }
            
            let code = String(Int.random(in: 100000...999999))
            let record = CKRecord(recordType: "PairingSession")
            record["code"] = code
            record["initiatorID"] = myID
            record["expiresAt"] = Date().addingTimeInterval(Config.pairingTTL)
            record["used"] = false
            
            self.database.save(record) { [weak self] savedRecord, error in
                guard let self = self else { return }
                
                if error == nil {
                    #if DEBUG
                    print("Pairing code generated: \(code)")
                    #endif
                    DispatchQueue.main.async {
                        if let rID = savedRecord?.recordID {
                            self.lastPairingRecordID = rID
                            self.subscribeToPairingUpdate(recordID: rID)
                        }
                        self.errorMessage = nil
                    }
                    completion(code)
                } else {
                    #if DEBUG
                    print("Error generating code: \(error?.localizedDescription ?? "")")
                    #endif
                    self.setErrorOnMain(.sendFailed(error?.localizedDescription ?? "Bilinmeyen Hata"))
                    completion(nil)
                }
            }
        }
    }
    
    private func invalidatePreviousSessions(completion: @escaping () -> Void) {
        guard let myID = currentUserID else {
            completion()
            return
        }
        
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
                    #if DEBUG
                    print("Invalidated \(recordsToDelete.count) old sessions.")
                    #endif
                    completion()
                }
                self?.database.add(modifyOp)
                
            case .failure(let error):
                #if DEBUG
                print("Failed to fetch old sessions for invalidation: \(error.localizedDescription)")
                #endif
                // Proceed anyway, not blocking
                completion()
            }
        }
    }
    
    func enterPairingCode(_ code: String, completion: @escaping (Bool) -> Void) {
        // Input validation
        let sanitizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedCode.count == Config.pairingCodeLength,
              sanitizedCode.allSatisfy({ $0.isNumber }) else {
            setErrorOnMain(.invalidCodeFormat)
            completion(false)
            return
        }
        
        let predicate = NSPredicate(format: "code == %@", sanitizedCode)
        let query = CKQuery(recordType: "PairingSession", predicate: predicate)
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1) { [weak self] (result: Result<(matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?), Error>) in
            switch result {
            case .success(let (results, _)):
                guard let match = results.first else {
                    self?.setErrorOnMain(.codeNotFound)
                    completion(false)
                    return
                }
                
                guard let self = self,
                      let record = try? match.1.get(),
                      let myID = self.currentUserID else {
                    completion(false)
                    return
                }
                
                // Check expiration
                if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                    self.setErrorOnMain(.pairingExpired)
                    completion(false)
                    return
                }
                
                // Check if already used
                if (record["used"] as? Bool) == true || record["receiverID"] != nil {
                    self.setErrorOnMain(.codeAlreadyUsed)
                    completion(false)
                    return
                }
                
                // Update session with receiver ID
                record["receiverID"] = myID
                record["used"] = true
                
                let modifyOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                modifyOp.savePolicy = .changedKeys
                modifyOp.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        if let initiatorID = record["initiatorID"] as? String {
                            DispatchQueue.main.async {
                                self.partnerID = initiatorID
                                self.isPaired = true
                                self.subscribeToHeartbeats()
                                completion(true)
                            }
                        } else {
                            completion(false)
                        }
                    case .failure(let error):
                        #if DEBUG
                        print("Modify failed: \(error.localizedDescription)")
                        #endif
                        self.setErrorOnMain(.pairingFailed(error.localizedDescription))
                        completion(false)
                    }
                }
                self.database.add(modifyOp)
                
            case .failure(let error):
                #if DEBUG
                print("Fetch failed: \(error.localizedDescription)")
                #endif
                self?.setErrorOnMain(.fetchFailed(error.localizedDescription))
                completion(false)
            }
        }
    }
    
    private func subscribeToPairingUpdate(recordID: CKRecord.ID) {
        let subscriptionID = SubscriptionIDs.pairing(recordID.recordName)
        let subscription = CKQuerySubscription(
            recordType: "PairingSession",
            predicate: NSPredicate(format: "recordID == %@", recordID),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]
        )
        
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.category = "Pairing"
        subscription.notificationInfo = info
        
        database.save(subscription) { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error as? CKError {
                if self.shouldTreatSubscriptionAsSuccess(error) {
                    DispatchQueue.main.async {
                        self.pairingSubscribed = true
                        self.errorMessage = nil
                    }
                } else {
                    #if DEBUG
                    print("Subscription failed: \(error.localizedDescription)")
                    #endif
                    DispatchQueue.main.async {
                        self.errorMessage = "Eşleşme bildirimi abonesi kurulamadı. Tekrar deneyin."
                        self.pairingSubscribed = false
                    }
                }
            } else {
                #if DEBUG
                print("Listening for pairing completion...")
                #endif
                DispatchQueue.main.async {
                    self.pairingSubscribed = true
                }
            }
        }
    }
    
    func checkPairingStatus(recordID: CKRecord.ID) {
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let record = record, let receiverID = record["receiverID"] as? String {
                DispatchQueue.main.async {
                    self.lastPairingRecordID = recordID
                }
                
                if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                    self.setErrorOnMain(.pairingExpired)
                    return
                }
                
                DispatchQueue.main.async {
                    self.partnerID = receiverID
                    self.isPaired = true
                    self.subscribeToHeartbeats()
                }
            }
        }
    }
    
    // MARK: - Heartbeat
    
    func sendHeartbeat(completion: @escaping (Bool) -> Void = { _ in }) {
        // Prevent concurrent sending (Race condition fix)
        guard !isSendingHeartbeat else {
            completion(false)
            return
        }
        
        // Set immediately after guard to prevent race conditions
        isSendingHeartbeat = true
        
        // Debounce: prevent rapid fire
        if let last = lastHeartbeatAttempt, Date().timeIntervalSince(last) < Config.heartbeatCooldown {
            isSendingHeartbeat = false
            completion(false)
            return
        }
        lastHeartbeatAttempt = Date()
        
        guard let myID = currentUserID, let pID = partnerID else {
            DispatchQueue.main.async {
                self.errorMessage = "Eşleşme yok. Önce bağlanın."
                self.isSendingHeartbeat = false
            }
            completion(false)
            return
        }
        
        // Prevent self-loop
        if myID == pID {
            setErrorOnMain(.selfPairing)
            DispatchQueue.main.async {
                self.isSendingHeartbeat = false
            }
            completion(false)
            return
        }
        
        guard permissionStatus == .available else {
            DispatchQueue.main.async {
                self.errorMessage = "iCloud çevrimdışı. Gönderilemedi."
                self.isSendingHeartbeat = false
            }
            completion(false)
            return
        }
        
        let timestamp = Date()
        let record = CKRecord(recordType: "Heartbeat")
        record["fromID"] = myID
        record["toID"] = pID
        record["timestamp"] = timestamp
        
        sendHeartbeatWithTimeout(record: record, timestamp: timestamp, timeout: Config.heartbeatTimeout, attempt: 1, completion: completion)
    }
    
    private func sendHeartbeatWithTimeout(record: CKRecord, timestamp: Date, timeout: TimeInterval, attempt: Int, completion: @escaping (Bool) -> Void) {
        var completed = false
        
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !completed {
                completed = true
                #if DEBUG
                print("Heartbeat send timeout (attempt \(attempt))")
                #endif
                DispatchQueue.main.async {
                    self.errorMessage = "Bağlantı zaman aşımına uğradı."
                    self.isSendingHeartbeat = false
                }
                completion(false)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        
        database.save(record) { [weak self] savedRecord, error in
            guard let self = self else { return }
            guard !completed else { return }
            
            completed = true
            timeoutWork.cancel()
            
            if let error = error {
                #if DEBUG
                print("Failed to send heartbeat (attempt \(attempt)): \(error.localizedDescription)")
                #endif
                
                // Retry on network error with exponential backoff
                if attempt < Config.maxRetryAttempts && self.isNetworkRelated(error) {
                    let delay = self.retryDelay(for: attempt)
                    #if DEBUG
                    print("Network error detected, retrying in \(delay)s...")
                    #endif
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.sendHeartbeatWithTimeout(record: record, timestamp: timestamp, timeout: Config.heartbeatTimeout, attempt: attempt + 1, completion: completion)
                    }
                    return
                }
                
                // Handle final failure
                DispatchQueue.main.async {
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .networkUnavailable, .networkFailure:
                            self.setError(.networkUnavailable)
                        case .serviceUnavailable:
                            self.setError(.serviceUnavailable)
                        case .requestRateLimited:
                            self.setError(.rateLimited)
                        default:
                            self.setError(.sendFailed(error.localizedDescription))
                        }
                    } else {
                        self.setError(.sendFailed(error.localizedDescription))
                    }
                    self.isSendingHeartbeat = false
                }
                completion(false)
            } else {
                #if DEBUG
                print("Heartbeat sent successfully! (attempt \(attempt))")
                #endif
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.lastSentAt = timestamp
                    self.isSendingHeartbeat = false
                }
                completion(true)
            }
        }
    }
    
    // MARK: - Retry Logic
    private func retryDelay(for attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(attempt - 1)), 30.0) // Max 30 seconds
    }
    
    // MARK: - Self Test
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
        
        DispatchQueue.main.async {
            self.healthChecks = results
        }
    }
    
    // MARK: - Subscriptions
    
    func subscribeToHeartbeats() {
        // Prevent duplicate subscriptions
        guard !heartbeatSubscribed else { return }
        guard let myID = currentUserID else { return }
        
        let subscriptionID = SubscriptionIDs.heartbeat
        let predicate = NSPredicate(format: "toID == %@ AND fromID != %@", myID, myID)
        let subscription = CKQuerySubscription(
            recordType: "Heartbeat",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "Özledimmm Aşkımıı 🧡"
        info.soundName = "default"
        info.shouldBadge = true
        info.category = "Heartbeat"
        subscription.notificationInfo = info
        
        database.save(subscription) { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error as? CKError {
                #if DEBUG
                print("Heartbeat subscription result: \(error.localizedDescription)")
                #endif
                DispatchQueue.main.async {
                    if self.shouldTreatSubscriptionAsSuccess(error) {
                        self.errorMessage = nil
                        self.heartbeatSubscribed = true
                    } else {
                        self.errorMessage = "Bildirim hatası: \(error.localizedDescription)"
                        self.heartbeatSubscribed = false
                    }
                }
            } else {
                #if DEBUG
                print("Subscribed to heartbeats.")
                #endif
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.heartbeatSubscribed = true
                }
            }
        }
    }
    
    func refreshSubscriptions() {
        // Reset subscription status to allow re-subscription
        heartbeatSubscribed = false
        pairingSubscribed = false
        
        subscribeToHeartbeats()
        if let recordID = lastPairingRecordID {
            subscribeToPairingUpdate(recordID: recordID)
        }
    }
    
    func refreshPairingStatus() {
        if let recordID = lastPairingRecordID {
            checkPairingStatus(recordID: recordID)
        } else if partnerID != nil {
            // Already paired locally
            isPaired = true
        }
    }
    
    // MARK: - Network Helpers
    
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
        let description = error.localizedDescription.lowercased()
        
        // These indicate subscription already exists (which is fine)
        let successIndicators = [
            "exists",
            "already",
            "duplicate",
            "production container",  // This error means it exists in production
            "subscription with id"   // Part of "subscription with id X already exists"
        ]
        
        // Check if error code indicates server rejected due to existing subscription
        if error.code == .serverRejectedRequest {
            return successIndicators.contains { description.contains($0) }
        }
        
        // Also check for any success indicator in the description
        return successIndicators.contains { description.contains($0) }
    }
    
    // MARK: - Push Registration
    
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
    
    // MARK: - Unpair
    
    func unpair() {
        let cleanup = { [weak self] in
            DispatchQueue.main.async {
                self?.partnerID = nil
                self?.isPaired = false
                self?.lastPairingRecordID = nil
                self?.lastSentAt = nil
                self?.lastReceivedAt = nil
                self?.errorMessage = nil
                self?.heartbeatSubscribed = false
                self?.pairingSubscribed = false
            }
        }
        
        invalidatePreviousSessions {
            cleanup()
        }
    }
    
    // MARK: - Heartbeat Received
    
    func markHeartbeatReceived(at date: Date = Date()) {
        DispatchQueue.main.async {
            self.lastReceivedAt = date
        }
    }
}
