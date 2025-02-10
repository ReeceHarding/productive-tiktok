import XCTest
@testable import ProductivityTalk_2

final class SchedulingViewModelTests: XCTestCase {
    var sut: SchedulingViewModel!
    
    override func setUp() {
        super.setUp()
        sut = SchedulingViewModel()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testGenerateEventProposal_Success() async throws {
        // Given
        let transcript = "Let's schedule a team meeting next week to discuss the project roadmap"
        let timeOfDay = "morning"
        let userPrompt = "Make it a 1-hour meeting"
        
        // When
        try await sut.generateEventProposal(
            transcript: transcript,
            timeOfDay: timeOfDay,
            userPrompt: userPrompt
        )
        
        // Then
        XCTAssertNotNil(sut.eventProposal)
        XCTAssertFalse(sut.eventProposal?.title.isEmpty ?? true)
        XCTAssertFalse(sut.eventProposal?.description.isEmpty ?? true)
        XCTAssertGreaterThan(sut.eventProposal?.durationMinutes ?? 0, 0)
    }
    
    func testFindAvailableTimeSlots_Success() async throws {
        // Given
        let durationMinutes = 60
        
        // When
        try await sut.findAvailableTimeSlots(forDuration: durationMinutes)
        
        // Then
        XCTAssertFalse(sut.availableTimeSlots.isEmpty)
        
        // Verify each slot is long enough
        for slot in sut.availableTimeSlots {
            XCTAssertGreaterThanOrEqual(slot.duration / 60, Double(durationMinutes))
        }
    }
    
    func testScheduleEvent_Success() async throws {
        // Given
        let title = "Team Planning Meeting"
        let description = "Discuss Q2 roadmap and priorities"
        let startTime = Date().addingTimeInterval(24 * 60 * 60) // Tomorrow
        let durationMinutes = 60
        
        // When/Then
        // This should not throw
        try await sut.scheduleEvent(
            title: title,
            description: description,
            startTime: startTime,
            durationMinutes: durationMinutes
        )
    }
    
    func testGenerateEventProposal_EmptyTranscript() async {
        // Given
        let transcript = ""
        let timeOfDay = "morning"
        let userPrompt = ""
        
        // When/Then
        do {
            try await sut.generateEventProposal(
                transcript: transcript,
                timeOfDay: timeOfDay,
                userPrompt: userPrompt
            )
            XCTFail("Expected error for empty transcript")
        } catch {
            // Success - error was thrown
        }
    }
    
    func testFindAvailableTimeSlots_InvalidDuration() async {
        // Given
        let durationMinutes = -30 // Invalid duration
        
        // When/Then
        do {
            try await sut.findAvailableTimeSlots(forDuration: durationMinutes)
            XCTFail("Expected error for negative duration")
        } catch {
            // Success - error was thrown
        }
    }
    
    func testScheduleEvent_PastStartTime() async {
        // Given
        let title = "Past Meeting"
        let description = "Should fail"
        let startTime = Date().addingTimeInterval(-24 * 60 * 60) // Yesterday
        let durationMinutes = 60
        
        // When/Then
        do {
            try await sut.scheduleEvent(
                title: title,
                description: description,
                startTime: startTime,
                durationMinutes: durationMinutes
            )
            XCTFail("Expected error for past start time")
        } catch {
            // Success - error was thrown
        }
    }
} 