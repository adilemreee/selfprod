import SwiftUI

struct ContentView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    
    // Simulator bypass for testing (DEBUG only)
    #if DEBUG
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    #endif
    
    var body: some View {
        Group {
            #if DEBUG
            if isSimulator || cloudManager.isPaired {
                HeartView()
            } else {
                PairingView()
            }
            #else
            if cloudManager.isPaired {
                HeartView()
            } else {
                PairingView()
            }
            #endif
        }
        .animation(.default, value: cloudManager.isPaired)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
