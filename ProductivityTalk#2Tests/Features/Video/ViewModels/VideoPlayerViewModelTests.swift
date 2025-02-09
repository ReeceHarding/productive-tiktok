import XCTest
import AVKit
import FirebaseFirestore
@testable import ProductivityTalk_2

// Mock Firestore
class MockFirestore: Firestore {
    var updateDataCalled = false
    var updateDataError: Error?
    
    required init() {
        super.init()
    }
    
    override func collection(_ collectionPath: String) -> CollectionReference {
        return MockCollectionReference(firestore: self, path: collectionPath)
    }
}

class MockCollectionReference: CollectionReference, @unchecked Sendable {
    required init(firestore: Firestore, path: String) {
        super.init(firestore: firestore, path: path)
    }
    
    override func document(_ documentPath: String) -> DocumentReference {
        return MockDocumentReference(firestore: self.firestore, path: "\(path)/\(documentPath)")
    }
}

class MockDocumentReference: DocumentReference, @unchecked Sendable {
    required init(firestore: Firestore, path: String) {
        super.init(firestore: firestore, path: path)
    }
    
    override func updateData(_ fields: [AnyHashable : Any]) async throws {
        // Simulate success
    }
}

@MainActor
final class VideoPlayerViewModelTests: XCTestCase {
    var sut: VideoPlayerViewModel!
    var mockVideo: Video!
    var mockFirestore: MockFirestore!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockVideo = Video(
            id: "test-id",
            ownerId: "test-owner",
            videoURL: "https://example.com/test.mp4",
            thumbnailURL: "https://example.com/test.jpg",
            title: "Test Video",
            tags: ["test"],
            description: "Test Description",
            ownerUsername: "testUser"
        )
        
        mockFirestore = MockFirestore()
        sut = VideoPlayerViewModel(video: mockVideo)
        // Inject mock Firestore
        let mirror = Mirror(reflecting: sut!)
        if let firestoreProperty = mirror.children.first(where: { $0.label == "firestore" }) {
            let firestoreObject = firestoreProperty.value as AnyObject
            // Use Objective-C runtime to set the private property
            object_setClass(firestoreObject, MockFirestore.self)
        }
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockVideo = nil
        mockFirestore = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async {
        XCTAssertEqual(sut.video.id, mockVideo.id)
        XCTAssertEqual(sut.brainCount, mockVideo.brainCount)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
        XCTAssertFalse(sut.showBrainAnimation)
        XCTAssertFalse(sut.isInSecondBrain)
        XCTAssertTrue(sut.showControls)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.watchTime, 0.0)
    }
    
    // MARK: - Video Loading Tests
    
    func testVideoLoading() async {
        // Initial state
        XCTAssertNil(sut.player)
        XCTAssertFalse(sut.isLoading)
        
        // Start loading
        sut.loadVideo()
        
        // Loading state
        XCTAssertTrue(sut.isLoading)
        
        // Wait for loading to complete (in real tests we'd mock this)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Final state
        XCTAssertFalse(sut.isLoading)
        
        if let error = sut.error {
            XCTFail("Video loading failed with error: \(error)")
        }
    }
    
    // MARK: - Second Brain Tests
    
    func testSecondBrainAdd() async throws {
        // Initial state
        XCTAssertFalse(sut.isInSecondBrain)
        
        // Add to second brain
        try await sut.addToSecondBrain()
        
        // Should be in second brain
        XCTAssertTrue(sut.isInSecondBrain)
        XCTAssertEqual(sut.brainCount, 1)
    }
    
    // MARK: - Playback Control Tests
    
    func testPlaybackControls() async {
        // Start playback
        await sut.play()
        XCTAssertTrue(sut.isPlaying)
        
        // Pause playback
        await sut.pause()
        XCTAssertFalse(sut.isPlaying)
        
        // Initial controls state
        XCTAssertTrue(sut.showControls)
        
        // Toggle controls
        sut.toggleControls()
        XCTAssertFalse(sut.showControls)
    }
    
    // MARK: - Watch Time Tests
    
    func testWatchTimeTracking() async {
        // Initial state
        XCTAssertEqual(sut.watchTime, 0.0)
        
        // Start playback
        await sut.play()
        
        // Wait for some time to accumulate
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Should have accumulated some watch time
        XCTAssertGreaterThan(sut.watchTime, 0.0)
    }
} 