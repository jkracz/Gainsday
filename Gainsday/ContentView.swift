import SwiftUI
import Playgrounds

struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "Gainsday",
            systemImage: "figure.run",
            description: Text("Your workouts will appear in your calendar.")
        )
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
