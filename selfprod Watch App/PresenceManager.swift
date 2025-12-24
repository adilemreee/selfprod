import CoreLocation
import CloudKit
import Combine

/// Manages proximity detection between paired partners
/// Uses CoreLocation to track user location and CloudKit to sync with partner
class PresenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PresenceManager()
    
    // MARK: - Configuration
    private enum Config {
        /// Distance threshold in meters to consider "nearby"
        static let proximityThreshold: CLLocationDistance = 100.0
        
        /// Minimum time between location updates to CloudKit (seconds)
        static let locationUpdateInterval: TimeInterval = 5 * 60 // 5 minutes
        
        /// Minimum distance change to trigger update (meters)
        static let distanceFilter: CLLocationDistance = 50.0
        
        /// Cooldown between encounter notifications (seconds)
        static let encounterCooldown: TimeInterval = 30 * 60 // 30 minutes
        
        /// Location record TTL (seconds)
        static let locationTTL: TimeInterval = 15 * 60 // 15 minutes
    }
    
    private enum StorageKeys {
        static let presenceEnabled = "PresenceTrackingEnabled"
        static let lastEncounterTime = "LastEncounterTime"
    }
    
    // MARK: - Properties
    private let locationManager = CLLocationManager()
    private let container = CKContainer(identifier: "iCloud.com.adilemre.selfprod")
    private lazy var database = container.publicCloudDatabase
    
    private var lastLocationUpdate: Date?
    private var lastEncounterTime: Date?
    private var locationSubscribed = false
    
    // MARK: - Published Properties
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: StorageKeys.presenceEnabled)
            if isEnabled {
                startTracking()
            } else {
                stopTracking()
            }
        }
    }
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var partnerLocation: CLLocation?
    @Published var partnerLocationTimestamp: Date?
    @Published var isNearPartner: Bool = false
    @Published var distanceToPartner: CLLocationDistance?
    @Published var lastEncounter: Date?
    @Published var errorMessage: String?
    
    // MARK: - Initialization
    private override init() {
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = Config.distanceFilter
        
        // Load saved state
        isEnabled = UserDefaults.standard.bool(forKey: StorageKeys.presenceEnabled)
        lastEncounterTime = UserDefaults.standard.object(forKey: StorageKeys.lastEncounterTime) as? Date
        lastEncounter = lastEncounterTime
        
        // Check current authorization
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Authorization
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Tracking Control
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestAuthorization()
            return
        }
        
        locationManager.startUpdatingLocation()
        subscribeToPartnerLocation()
        
        #if DEBUG
        print("Presence tracking started")
        #endif
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        
        #if DEBUG
        print("Presence tracking stopped")
        #endif
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        // Check if we should update CloudKit
        if shouldUpdateCloudKit() {
            updateLocationInCloudKit(location)
        }
        
        // Check proximity to partner
        checkProximity()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
        
        DispatchQueue.main.async {
            self.errorMessage = "Konum alınamadı: \(error.localizedDescription)"
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            
            if self.isEnabled && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) {
                self.startTracking()
            }
        }
    }
    
    // MARK: - CloudKit Location Sync
    private func shouldUpdateCloudKit() -> Bool {
        guard let lastUpdate = lastLocationUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) >= Config.locationUpdateInterval
    }
    
    private func updateLocationInCloudKit(_ location: CLLocation) {
        guard let myID = CloudKitManager.shared.currentUserID else { return }
        
        lastLocationUpdate = Date()
        
        // First, delete old location records
        deleteOldLocationRecords(for: myID) { [weak self] in
            guard let self = self else { return }
            
            // Create new location record
            let record = CKRecord(recordType: "UserLocation")
            record["userID"] = myID
            record["latitude"] = location.coordinate.latitude
            record["longitude"] = location.coordinate.longitude
            record["timestamp"] = Date()
            record["expiresAt"] = Date().addingTimeInterval(Config.locationTTL)
            
            self.database.save(record) { savedRecord, error in
                if let error = error {
                    #if DEBUG
                    print("Failed to save location: \(error.localizedDescription)")
                    #endif
                } else {
                    #if DEBUG
                    print("Location updated in CloudKit")
                    #endif
                }
            }
        }
    }
    
    private func deleteOldLocationRecords(for userID: String, completion: @escaping () -> Void) {
        let predicate = NSPredicate(format: "userID == %@", userID)
        let query = CKQuery(recordType: "UserLocation", predicate: predicate)
        
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
                    completion()
                }
                self?.database.add(modifyOp)
                
            case .failure:
                completion()
            }
        }
    }
    
    // MARK: - Partner Location Subscription
    private func subscribeToPartnerLocation() {
        guard !locationSubscribed else { return }
        guard let partnerID = CloudKitManager.shared.partnerID else { return }
        
        let subscriptionID = "PartnerLocation-Sub"
        let predicate = NSPredicate(format: "userID == %@", partnerID)
        let subscription = CKQuerySubscription(
            recordType: "UserLocation",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.category = "PartnerLocation"
        subscription.notificationInfo = info
        
        database.save(subscription) { [weak self] _, error in
            if let error = error as? CKError {
                let description = error.localizedDescription.lowercased()
                if description.contains("already exists") || description.contains("duplicate") {
                    self?.locationSubscribed = true
                }
            } else {
                self?.locationSubscribed = true
                #if DEBUG
                print("Subscribed to partner location updates")
                #endif
            }
        }
    }
    
    // MARK: - Fetch Partner Location
    func fetchPartnerLocation() {
        guard let partnerID = CloudKitManager.shared.partnerID else { return }
        
        let predicate = NSPredicate(format: "userID == %@", partnerID)
        let query = CKQuery(recordType: "UserLocation", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1) { [weak self] result in
            switch result {
            case .success(let (results, _)):
                guard let match = results.first,
                      let record = try? match.1.get(),
                      let lat = record["latitude"] as? Double,
                      let lon = record["longitude"] as? Double else {
                    // No location found - clear partner location
                    DispatchQueue.main.async {
                        self?.partnerLocation = nil
                        self?.partnerLocationTimestamp = nil
                        self?.distanceToPartner = nil
                        self?.isNearPartner = false
                    }
                    return
                }
                
                // Check if expired
                if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                    // Location expired - clear it
                    DispatchQueue.main.async {
                        self?.partnerLocation = nil
                        self?.partnerLocationTimestamp = nil
                        self?.distanceToPartner = nil
                        self?.isNearPartner = false
                    }
                    return
                }
                
                let location = CLLocation(latitude: lat, longitude: lon)
                let timestamp = record["timestamp"] as? Date ?? Date()
                
                DispatchQueue.main.async {
                    self?.partnerLocation = location
                    self?.partnerLocationTimestamp = timestamp
                    self?.checkProximity()
                }
                
            case .failure(let error):
                #if DEBUG
                print("Failed to fetch partner location: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // MARK: - Proximity Detection
    private func checkProximity() {
        guard let myLocation = currentLocation,
              let partnerLoc = partnerLocation else {
            DispatchQueue.main.async {
                self.isNearPartner = false
                self.distanceToPartner = nil
            }
            return
        }
        
        let distance = myLocation.distance(from: partnerLoc)
        
        DispatchQueue.main.async {
            self.distanceToPartner = distance
            
            let wasNear = self.isNearPartner
            self.isNearPartner = distance <= Config.proximityThreshold
            
            // Trigger encounter notification if just became near
            if self.isNearPartner && !wasNear {
                self.handleEncounter()
            }
        }
    }
    
    // MARK: - Encounter Handling
    private func handleEncounter() {
        // Check cooldown
        if let lastEncounter = lastEncounterTime,
           Date().timeIntervalSince(lastEncounter) < Config.encounterCooldown {
            #if DEBUG
            print("Encounter cooldown active, skipping notification")
            #endif
            return
        }
        
        lastEncounterTime = Date()
        UserDefaults.standard.set(lastEncounterTime, forKey: StorageKeys.lastEncounterTime)
        
        DispatchQueue.main.async {
            self.lastEncounter = self.lastEncounterTime
        }
        
        // Create encounter record in CloudKit
        createEncounterRecord()
        
        // Post local notification
        NotificationCenter.default.post(name: .encounterDetected, object: nil)
        
        #if DEBUG
        print("Encounter detected! Distance: \(distanceToPartner ?? 0)m")
        #endif
    }
    
    private func createEncounterRecord() {
        guard let myID = CloudKitManager.shared.currentUserID,
              let partnerID = CloudKitManager.shared.partnerID else { return }
        
        let record = CKRecord(recordType: "Encounter")
        record["user1ID"] = myID
        record["user2ID"] = partnerID
        record["timestamp"] = Date()
        record["latitude"] = currentLocation?.coordinate.latitude ?? 0
        record["longitude"] = currentLocation?.coordinate.longitude ?? 0
        
        database.save(record) { _, error in
            if let error = error {
                #if DEBUG
                print("Failed to save encounter: \(error.localizedDescription)")
                #endif
            } else {
                #if DEBUG
                print("Encounter saved to CloudKit")
                #endif
            }
        }
    }
    
    // MARK: - Cleanup
    func clearLocationData() {
        guard let myID = CloudKitManager.shared.currentUserID else { return }
        deleteOldLocationRecords(for: myID) {}
        
        DispatchQueue.main.async {
            self.currentLocation = nil
            self.partnerLocation = nil
            self.isNearPartner = false
            self.distanceToPartner = nil
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let encounterDetected = Notification.Name("EncounterDetected")
    static let partnerLocationUpdated = Notification.Name("PartnerLocationUpdated")
}

// MARK: - Distance Formatting Extension
extension CLLocationDistance {
    var formattedDistance: String {
        if self < 1000 {
            return String(format: "%.0f m", self)
        } else {
            return String(format: "%.1f km", self / 1000)
        }
    }
}
