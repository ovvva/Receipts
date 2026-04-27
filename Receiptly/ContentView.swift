import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            
            Text("Receiptly")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Button(action: {
                print("Scan button tapped")
            }) {
                Text("Scan Receipt")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
        }
    }
}

#Preview {
    ContentView()
}
