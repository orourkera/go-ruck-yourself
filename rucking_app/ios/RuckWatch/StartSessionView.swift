import SwiftUI

struct StartSessionView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var ruckWeight: Double = 10.0 // Default weight
    
    var body: some View {
        VStack {
            Text("Rucking App")
                .font(.title2)
                .bold()
                .padding(.bottom, 20)
            
            Text("Ruck Weight: \(Int(ruckWeight)) kg")
                .padding(.bottom, 5)
            
            Slider(value: $ruckWeight, in: 5...40, step: 1)
                .padding(.horizontal)
            
            Button(action: {
                sessionManager.startSession(weight: ruckWeight)
            }) {
                Text("Start Session")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(12)
            }
            .padding(.top, 20)
            
            Text("or")
                .foregroundColor(.gray)
                .padding(.vertical, 10)
            
            Text("Start from Phone")
                .foregroundColor(.blue)
                .underline()
        }
        .padding()
    }
}
