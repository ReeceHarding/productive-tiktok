import SwiftUI

struct AuthenticationView: View {
    @State var showSignUp: Bool
    
    var body: some View {
        if showSignUp {
            SignUpView()
        } else {
            SignInView()
        }
    }
}

#Preview {
    AuthenticationView(showSignUp: true)
} 