import SwiftUI
import Combine

struct PairingView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    @State private var generatedCode: String?
    @State private var enteredCode: String = ""
    @State private var isEnteringCode = false
    @State private var isLoading = false
    
    // Modern Gradient Background
    let bgGradient = RadialGradient(
        gradient: Gradient(colors: [Color(red: 0.1, green: 0.05, blue: 0.15), Color.black]),
        center: .center,
        startRadius: 10,
        endRadius: 180
    )
    
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 5) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
                        
                        Text("Eşleştirme")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 10)
                    
                    if let errorMessage = cloudManager.errorMessage {
                        VStack(spacing: 6) {
                            Text(errorMessage)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.12))
                                )
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    cloudManager.checkAccountStatus()
                                }) {
                                    Text("Tekrar Dene")
                                        .font(.caption)
                                }
                                
                                Button(action: {
                                    cloudManager.retryIdentityFetch()
                                }) {
                                    Text("Kimliği Yenile")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    
                    if let code = generatedCode {
                        // Generated Code Card
                        VStack(spacing: 10) {
                            Text("Senin Kodun")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.gray)
                            
                            Text(code)
                                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .padding(.horizontal)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.15))
                                        .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
                                )
                            
                            Text("Bu kodu partnerine gönder")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        )
                        
                        // Waiting indicator
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white)
                            Text("Partner bekleniyor...")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 5)
                        
                        Button(action: {
                            cloudManager.refreshPairingStatus()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Durumu Kontrol Et")
                            }
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 5)
                        
                    } else if !isEnteringCode {
                        // Main Action Buttons
                        VStack(spacing: 15) {
                            ModernButton(title: "Kod Oluştur", icon: "sparkles", color: .pink) {
                                generateCode()
                            }
                            .disabled(isLoading)
                            
                            ModernButton(title: "Kodu Gir", icon: "keyboard", color: .purple) {
                                isEnteringCode = true
                            }
                            .disabled(isLoading)
                            
                            if cloudManager.errorMessage != nil {
                                ModernButton(title: "Yeniden Dene", icon: "arrow.clockwise", color: .orange) {
                                    cloudManager.checkAccountStatus()
                                }
                                .disabled(isLoading)
                            }
                        }
                    }
                    
                    if isEnteringCode {
                        // Code Entry Section
                        VStack(spacing: 15) {
                            TextField("Kodu Buraya Yaz", text: $enteredCode)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .frame(height: 50)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(enteredCode.count == 6 ? Color.green : Color.white.opacity(0.3), lineWidth: 1)
                                )
                            
                            if isLoading {
                                ProgressView()
                                    .tint(.pink)
                            } else {
                                Button(action: {
                                    pairWithCode()
                                }) {
                                    Text("BAĞLAN")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .cornerRadius(25)
                                        .shadow(color: .green.opacity(0.4), radius: 5)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(enteredCode.count != 6)
                                .opacity(enteredCode.count == 6 ? 1.0 : 0.6)
                            }
                            
                            Button("Vazgeç") {
                                withAnimation {
                                    isEnteringCode = false
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
            }
        }
        .onReceive(timer) { _ in
            if generatedCode != nil && !cloudManager.isPaired {
                cloudManager.refreshPairingStatus()
            }
        }
    }
    
    private func generateCode() {
        withAnimation { isLoading = true }
        cloudManager.generatePairingCode { code in
            withAnimation {
                isLoading = false
                self.generatedCode = code
            }
        }
    }
    
    private func pairWithCode() {
        withAnimation { isLoading = true }
        cloudManager.enterPairingCode(enteredCode) { success in
            withAnimation { isLoading = false }
            if !success {
                // Haptic error
                print("Failed to pair")
            }
        }
    }
}

// Custom Modern Button Component
struct ModernButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    Capsule()
                        .fill(color.opacity(0.2))
                    Capsule()
                        .stroke(color.opacity(0.8), lineWidth: 1)
                }
            )
            .shadow(color: color.opacity(0.3), radius: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PairingView_Previews: PreviewProvider {
    static var previews: some View {
        PairingView()
    }
}
