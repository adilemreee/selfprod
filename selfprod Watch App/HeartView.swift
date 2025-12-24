import SwiftUI
import WatchKit
import Combine
import CloudKit

// MARK: - Modern Ripple Effect View (Dalga Efekti)
struct PulseWave: Identifiable {
    let id = UUID()
    var scale: CGFloat = 1.0
    var opacity: Double = 0.8
}

struct HeartRippleEffectView: View {
    @Binding var triggerBeat: Bool
    @State private var waves: [PulseWave] = []
    let baseSize: CGFloat
    let isReceivedMode: Bool
    
    var body: some View {
        ZStack {
            ForEach(waves) { wave in
                Image(systemName: "heart.fill")
                    .font(.system(size: baseSize))
                    .foregroundStyle(
                        .linearGradient(
                            colors: isReceivedMode ? [.yellow, .orange] : [.pink.opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Image(systemName: "heart")
                            .font(.system(size: baseSize * 1.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.3))
                    )
                    .scaleEffect(wave.scale)
                    .opacity(wave.opacity)
                    .blur(radius: 2)
            }
        }
        .onChange(of: triggerBeat) { _, _ in
            spawnWave()
        }
    }
    
    private func spawnWave() {
        let newWave = PulseWave()
        waves.append(newWave)
        
        withAnimation(.easeOut(duration: 0.8)) {
            if let index = waves.firstIndex(where: { $0.id == newWave.id }) {
                waves[index].scale = 3.0
                waves[index].opacity = 0.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            waves.removeAll { $0.id == newWave.id }
        }
    }
}

// MARK: - ULTRA MODERN PULSING HEART (Ana Animasyon)
struct PulsingHeartView: View {
    @Binding var receivedHeartbeat: Bool
    let onTap: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var innerLightIntensity: Double = 0.5
    @State private var glowRadius: CGFloat = 10
    @State private var glowOpacity: Double = 0.6
    @State private var triggerRippleSignal = false
    
    let baseFontSize: CGFloat = 80
    
    // Otomatik atış ritmi - autoconnect ile her zaman çalışır
    let heartbeatTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // KATMAN 0: Modern Dalga Efekti
            HeartRippleEffectView(
                triggerBeat: $triggerRippleSignal,
                baseSize: baseFontSize,
                isReceivedMode: receivedHeartbeat
            )
            
            // KATMAN 1: Ana Glow (Dış Işık Halesi)
            Image(systemName: "heart.fill")
                .font(.system(size: baseFontSize))
                .foregroundStyle(receivedHeartbeat ? Color.orange : Color.pink)
                .blur(radius: glowRadius)
                .opacity(glowOpacity)
                .scaleEffect(scale * 1.1)
            
            // Ana Buton ve Kalp Yapısı
            Button(action: {
                triggerManualBeat()
                onTap()
            }) {
                ZStack {
                    // KATMAN 2: Ana Neon Gövde
                    Image(systemName: "heart.fill")
                        .font(.system(size: baseFontSize))
                        .foregroundStyle(
                            LinearGradient(
                                colors: receivedHeartbeat ?
                                [.yellow, .orange, .red] :
                                [Color(red: 1.0, green: 0.2, blue: 0.6), Color(red: 0.8, green: 0.1, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: receivedHeartbeat ? .orange.opacity(0.8) : Color.pink.opacity(0.7),
                            radius: 8, x: 0, y: 0
                        )
                    
                    // KATMAN 3: İç Parlama
                    Image(systemName: "heart.fill")
                        .font(.system(size: baseFontSize))
                        .foregroundStyle(
                            LinearGradient(colors: [.white.opacity(innerLightIntensity), .clear], startPoint: .top, endPoint: .bottom)
                        )
                        .mask(
                            Image(systemName: "heart.fill")
                                .font(.system(size: baseFontSize * 0.9))
                                .offset(y: 3)
                        )
                        .blendMode(.overlay)
                }
                .scaleEffect(scale)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onReceive(heartbeatTimer) { _ in
            if !receivedHeartbeat {
                performModernHeartbeat()
            }
        }
        .onChange(of: receivedHeartbeat) { _, newValue in
            if newValue {
                performRapidExcitementHeartbeat()
            }
        }
    }
    
    // MARK: - Modern Animasyon Mantığı
    private func performModernHeartbeat() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4, blendDuration: 0)) {
            scale = 1.2
            innerLightIntensity = 0.9
            glowRadius = 20
            glowOpacity = 0.8
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            triggerRippleSignal.toggle()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                innerLightIntensity = 0.5
                glowRadius = 10
                glowOpacity = 0.6
            }
        }
    }
    
    private func triggerManualBeat() {
        withAnimation(.easeIn(duration: 0.05)) {
            scale = 0.9
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            triggerRippleSignal.toggle()
            // Haptic is handled in ContentView too, but good to have here for sync
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                scale = 1.35
                innerLightIntensity = 1.0
                glowRadius = 25
                glowOpacity = 1.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.0
                innerLightIntensity = 0.5
                glowRadius = 10
                glowOpacity = 0.6
            }
        }
    }
    
    private func performRapidExcitementHeartbeat() {
        let beatCount = 6
        let duration = 0.18
        
        for i in 0..<beatCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * duration)) {
                triggerRippleSignal.toggle()
                withAnimation(.spring(response: 0.12, dampingFraction: 0.4)) {
                    scale = 1.3
                    glowRadius = 30
                    glowOpacity = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + (duration * 0.5)) {
                    withAnimation(.easeOut(duration: 0.08)) {
                        scale = 1.0
                        glowRadius = 15
                        glowOpacity = 0.7
                    }
                }
            }
        }
    }
}

// MARK: - Modern Connection Status Pill
struct ModernStatusView: View {
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 5, height: 5)
                .shadow(color: isConnected ? .green : .red, radius: 2)
            
            Text(isConnected ? "Bağlı" : "Koptu")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(isConnected ? .white.opacity(0.8) : .red.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Floating Hearts (Arka Plan)
struct FloatingHeartsView: View {
    @Binding var isActive: Bool
    @State private var hearts: [FloatingHeart] = []
    
    var body: some View {
        ZStack {
            ForEach(hearts) { heart in
                Image(systemName: "heart.fill")
                    .font(.system(size: heart.size))
                    .foregroundColor(heart.color)
                    .position(heart.position)
                    .opacity(heart.opacity)
                    .blur(radius: 1)
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                createFloatingHearts()
            }
        }
    }
    
    func createFloatingHearts() {
        for i in 0..<10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                let heart = FloatingHeart(
                    id: UUID(),
                    position: CGPoint(x: CGFloat.random(in: 10...190), y: 210),
                    size: CGFloat.random(in: 8...16),
                    color: [Color.pink, Color.purple, Color.orange, Color.cyan].randomElement()!,
                    opacity: 0.7
                )
                hearts.append(heart)
                
                withAnimation(.easeOut(duration: 3.0)) {
                    if let index = hearts.firstIndex(where: { $0.id == heart.id }) {
                        hearts[index].position.y = -40
                        hearts[index].position.x += CGFloat.random(in: -30...30)
                        hearts[index].opacity = 0
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
                    hearts.removeAll { $0.id == heart.id }
                }
            }
        }
    }
}

struct FloatingHeart: Identifiable {
    let id: UUID
    var position: CGPoint
    var size: CGFloat
    var color: Color
    var opacity: Double
}

// MARK: - Message Capsule UI
struct MessageCapsule: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(color)
                    .shadow(color: color.opacity(0.5), radius: 5)
            )
            .padding(.bottom, 5)
    }
}

struct StatusRow: View {
    let title: String
    let icon: String
    let color: Color
    let date: Date?
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(relativeString(from: date))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func relativeString(from date: Date?) -> String {
        guard let date else { return "Henüz yok" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PresenceRow: View {
    let lastReceived: Date?
    private let onlineWindow: TimeInterval = 5 * 60
    
    // Timer to refresh every 30 seconds for real-time updates
    let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var refreshTrigger = false
    
    private var isOnline: Bool {
        // refreshTrigger dependency forces recalculation on timer tick
        let _ = refreshTrigger
        guard let last = lastReceived else { return false }
        return Date().timeIntervalSince(last) <= onlineWindow
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOnline ? "dot.radiowaves.left.and.right" : "zzz")
                .foregroundColor(isOnline ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Eş Durumu")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(statusText(isOnline: isOnline, last: lastReceived))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .onReceive(refreshTimer) { _ in
            refreshTrigger.toggle()
        }
    }
    
    private func statusText(isOnline: Bool, last: Date?) -> String {
        if isOnline { return "Çevrimiçi görünüyor" }
        guard let last else { return "Henüz kalp alınmadı" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Son kalp \(formatter.localizedString(for: last, relativeTo: Date()))"
    }
}

// MARK: - Proximity Section
struct ProximitySection: View {
    @ObservedObject var presenceManager = PresenceManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Toggle Row
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yakınlık Algılama")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(presenceManager.isEnabled ? "Açık" : "Kapalı")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Toggle("", isOn: $presenceManager.isEnabled)
                    .labelsHidden()
                    .tint(.cyan)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Status Row (only if enabled)
            if presenceManager.isEnabled {
                HStack(spacing: 10) {
                    Image(systemName: presenceManager.isNearPartner ? "figure.2" : "figure.walk")
                        .foregroundColor(presenceManager.isNearPartner ? .green : .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presenceManager.isNearPartner ? "Yakınınızda! 💕" : "Partner Mesafesi")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(presenceManager.isNearPartner ? .green : .white)
                        if let distance = presenceManager.distanceToPartner {
                            Text(distance.formattedDistance)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Text("Konum bekleniyor...")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(presenceManager.isNearPartner ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
                .cornerRadius(12)
                .animation(.easeInOut, value: presenceManager.isNearPartner)
                
                // Partner location timestamp
                if let timestamp = presenceManager.partnerLocationTimestamp {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10))
                            .foregroundColor(.cyan.opacity(0.7))
                        Text("Partner konumu: \(relativeString(from: timestamp))")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal)
                }
                
                // Last Encounter
                if let lastEncounter = presenceManager.lastEncounter {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Son Buluşma")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(relativeString(from: lastEncounter))
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
            }
            
            // Authorization warning
            if presenceManager.isEnabled && presenceManager.authorizationStatus != .authorizedWhenInUse && presenceManager.authorizationStatus != .authorizedAlways {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Konum izni gerekli")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.yellow)
                    Spacer()
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(12)
                .onTapGesture {
                    presenceManager.requestAuthorization()
                }
            }
        }
    }
    
    private func relativeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct HeartView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    @ObservedObject var presenceManager = PresenceManager.shared
    @ObservedObject var voiceManager = VoiceManager.shared
    
    @State private var showSentMessage = false
    @State private var receivedHeartbeat = false
    @State private var isSending = false
    @State private var lastSentTime: Date?
    @State private var showUnpairConfirmation = false
    // Since we are in HeartView, we are theoretically paired.
    // However, cloudManager.isPaired is the source of truth.
    
    let bgGradient = RadialGradient(
        gradient: Gradient(colors: [Color(red: 0.1, green: 0.05, blue: 0.15), Color.black]),
        center: .center,
        startRadius: 10,
        endRadius: 180
    )
    
    var body: some View {
        TabView {
            mainHeartPage
            voicePage
            statusPage
            healthPage
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .background(bgGradient.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HeartbeatReceived"))) { _ in
            receiveLove()
        }
    }
    
    private var mainHeartPage: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            
            FloatingHeartsView(isActive: $receivedHeartbeat)
            
            VStack {
                // ÜST KISIM
                VStack(spacing: 6) {
                    Text("ÖZLEDİM AŞKIMI")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .pink.opacity(0.4), radius: 3, x: 0, y: 0)
                    
                    ModernStatusView(isConnected: cloudManager.isPaired)
                }
                .padding(.top, 15)
                
                Spacer()
                
                // ORTA KISIM (KALP)
                PulsingHeartView(receivedHeartbeat: $receivedHeartbeat) {
                    sendLove()
                }
                .frame(maxHeight: .infinity)
                
                Spacer()
                
                // ALT KISIM (MESAJ)
                ZStack {
                    if showSentMessage {
                        MessageCapsule(text: "Aşkıma Kalp..💖", color: .pink)
                            .transition(.scale.combined(with: .opacity).animation(.spring))
                    } else if receivedHeartbeat {
                        MessageCapsule(text: "Aşkın Seni Düşünüyor..", color: .yellow)
                            .transition(.scale.combined(with: .opacity).animation(.spring))
                    } else {
                        Text("Aşkına dokunn")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                }
                .frame(height: 40)
                
                if let error = cloudManager.errorMessage {
                    Text(error)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                    
                    HStack(spacing: 8) {
                        if cloudManager.permissionStatus == .restricted || cloudManager.permissionStatus == .couldNotDetermine {
                            Text("iCloud kısıtlı, ayarları kontrol et.")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        Button("Aboneliği Yenile") {
                            CloudKitManager.shared.refreshSubscriptions()
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }
    
    private var statusPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 8)
                Text("Durum")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                StatusRow(title: "Son Gönderilen", icon: "paperplane.fill", color: .pink, date: cloudManager.lastSentAt)
                StatusRow(title: "Son Alınan", icon: "heart.circle.fill", color: .yellow, date: cloudManager.lastReceivedAt)
                PresenceRow(lastReceived: cloudManager.lastReceivedAt)
                
                // Proximity Section
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)
                
                Text("Yakınlık")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ProximitySection()
                
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)
                
                Button(action: {
                    showUnpairConfirmation = true
                }) {
                    Text("Eşleşmeyi Bitir")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                        .shadow(color: .red.opacity(0.4), radius: 5)
                }
                .buttonStyle(PlainButtonStyle())
                .alert("Eşleşmeyi Bitir", isPresented: $showUnpairConfirmation) {
                    Button("İptal", role: .cancel) { }
                    Button("Evet, Bitir", role: .destructive) {
                        cloudManager.unpair()
                    }
                } message: {
                    Text("Eşleşmeyi bitirmek istediğinden emin misin?")
                }
                
                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(bgGradient.ignoresSafeArea())
    }
    
    private var healthPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 8)
                Text("Self Test")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                Button(action: {
                    CloudKitManager.shared.runSelfTest()
                }) {
                    Text("Testi Çalıştır")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                
                if cloudManager.healthChecks.isEmpty {
                    Text("Henüz test çalıştırılmadı.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    ForEach(cloudManager.healthChecks) { item in
                        HStack {
                            Image(systemName: item.isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(item.isOK ? .green : .yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(item.detail)
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(bgGradient.ignoresSafeArea())
    }
    
    private var voicePage: some View {
        VStack(spacing: 12) {
            // Title
            Text("Sesli Mesaj")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.top, 8)
            
            Spacer()
            
            // Incoming Message
            if voiceManager.hasIncomingMessage {
                Button(action: {
                    voiceManager.playIncomingMessage()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: voiceManager.isPlaying ? "speaker.wave.2.fill" : "envelope.fill")
                            .foregroundColor(.yellow)
                            .symbolEffect(.pulse, isActive: voiceManager.hasIncomingMessage)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Sesli Mesaj Var!")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.yellow)
                                if voiceManager.incomingMessageDuration > 0 {
                                    Text("(\(Int(voiceManager.incomingMessageDuration))sn)")
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                        .foregroundColor(.yellow.opacity(0.8))
                                }
                            }
                            Text(voiceManager.isPlaying ? "Çalıyor..." : "Dinlemek için dokun")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
            
            // Record Button (Centered)
            VStack(spacing: 8) {
                ZStack {
                    // Progress ring
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: voiceManager.recordingProgress)
                        .stroke(
                            LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: voiceManager.recordingProgress)
                    
                    // Mic button
                    Button(action: {}) {
                        Image(systemName: voiceManager.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(voiceManager.isRecording ? .red : .white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.1)
                            .onEnded { _ in
                                voiceManager.startRecording()
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in
                                if voiceManager.isRecording {
                                    voiceManager.stopRecording()
                                }
                            }
                    )
                }
                
                // Instruction / Sent message
                if voiceManager.showSentMessage {
                    Text("Ses Gönderildi! 🎤")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(voiceManager.isRecording ? "Bırak → Gönder" : "Basılı Tut → Kaydet")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .animation(.easeInOut, value: voiceManager.showSentMessage)
            
            Spacer()
            
            // Error message
            if let error = voiceManager.errorMessage {
                Text(error)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
        }
        .background(bgGradient.ignoresSafeArea())
        .onAppear {
            voiceManager.subscribeToVoiceMessages()
            voiceManager.checkForIncomingMessages()
        }
    }
    
    func sendLove() {
        // Debouncing: 2 saniye içinde tekrar gönderilmesini engelle
        let now = Date()
        if let lastSent = lastSentTime, now.timeIntervalSince(lastSent) < 2.0 {
            print("Debounced: Too fast, ignoring tap")
            return
        }
        
        // Eğer zaten gönderiliyor ise tekrar gönderme
        guard !isSending else {
            print("Already sending, ignoring tap")
            return
        }
        
        // Gönderim başladı
        isSending = true
        lastSentTime = now
        
        // 1. Haptic & Hemen mesaj göster (anlık feedback)
        playAttentionHaptic()
        withAnimation {
            showSentMessage = true
        }
        
        // 2. CloudKit'e gönder
        cloudManager.sendHeartbeat { [self] success in
            DispatchQueue.main.async {
                self.isSending = false
                
                if success {
                    // 2 saniye sonra gönderildi mesajını kaldır
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            self.showSentMessage = false
                        }
                    }
                } else {
                    // Hata durumunda mesajı hemen kaldır
                    withAnimation {
                        self.showSentMessage = false
                    }
                    self.lastSentTime = nil
                }
            }
        }
    }
    
    func receiveLove() {
        // Trigger received animation state
        withAnimation {
            receivedHeartbeat = true
        }
        CloudKitManager.shared.markHeartbeatReceived()
        playAttentionHaptic() // Single strong haptic + sound
        
        // 4 saniye sonra gelen kalp efektini kapat
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation {
                receivedHeartbeat = false
            }
        }
    }
    
    // MARK: - Haptic Engine
    private func playAttentionHaptic() {
        // Single strong tap; .retry hissedilir ve tok
        WKInterfaceDevice.current().play(.success)
    }
}

struct HeartView_Previews: PreviewProvider {
    static var previews: some View {
        HeartView()
    }
}
