func updateStatistics() async {
    print("updateStatistics: Starting statistics update for user: \(userId)")

    // Assume filterArray is the array used for the "in" query.
    // If filterArray is obtained from some computed source, assign it to a local variable.
    let filterArray = self.someFilterArray  // Replace with your actual variable

    // Add guard statement to ensure the array is non-empty.
    guard !filterArray.isEmpty else {
        print("updateStatistics: Filter array is empty. Skipping Firestore query.")
        return
    }
    
    // Now build your Firestore query using an "in" filter.
    // For example:
    let query = firestore.collection("secondBrain")
        .whereField("someField", in: filterArray) // Update "someField" as needed
    
    // Make sure to mark async calls with `await` if the query returns an async result.
    do {
        let snapshot = try await query.getDocuments()
        print("updateStatistics: Successfully retrieved \(snapshot.documents.count) documents.")
        // Process snapshot...
        
    } catch {
        print("updateStatistics: Error fetching documents: \(error)")
        // Handle error appropriately.
    }
    
    // ... remaining code in updateStatistics
} 