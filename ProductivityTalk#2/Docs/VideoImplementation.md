# Video Implementation Guide

## Overview
This document describes the complete video playback and processing implementation, including scheduling integration.

## Components

### 1. VideoPlayerViewModel
- Handles video playback and state management
- Manages player lifecycle
- Handles audio fading and buffering
- Integrates with Second Brain features

### 2. Video Processing
```swift
// Processing flow:
1. Download video
2. Extract audio/transcript
3. Process with GPT
4. Store in Firestore
```

## Logging Implementation

Every operation is logged using LoggingService:

```swift
// Video operations
LoggingService.video("Starting loadVideo for \(videoId)", component: "Player")
LoggingService.debug("Player ready for \(videoId)", component: "Player")
LoggingService.error("Failed to load: \(error)", component: "Player")

// Second Brain operations
LoggingService.debug("Second brain status: \(isInSecondBrain)", component: "Player")
```

## State Management

1. **Loading States**
   - isLoading
   - loadingProgress
   - error handling

2. **Playback States**
   - isPlaying
   - isBuffering
   - showControls

3. **Second Brain States**
   - isInSecondBrain
   - brainCount
   - showBrainAnimation

## Memory Management

1. **Resource Cleanup**
   ```swift
   private func cleanup() async {
       // Invalidate observers
       // Remove time observer
       // Clean up player
       // Log cleanup
   }
   ```

2. **Preloading Strategy**
   - Preload next video
   - Cache management
   - Memory limits

## Error Handling

1. **Network Errors**
   - Retry logic
   - User feedback
   - Error logging

2. **Player Errors**
   - Status monitoring
   - Recovery attempts
   - Fallback options

## Testing

1. **Unit Tests**
   ```bash
   xcodebuild test -scheme ProductivityTalk#2 \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     -only-testing:VideoPlayerViewModelTests
   ```

2. **UI Tests**
   - Playback scenarios
   - User interactions
   - Error states

## Debugging

1. Check Xcode console for detailed logs:
   ```
   [Player] Starting loadVideo for <id>
   [Player] Buffer status: <status>
   [Player] Error: <details>
   ```

2. Common Issues:
   - Video loading failures
   - Memory warnings
   - Playback interruptions

## Performance Optimization

1. **Memory Usage**
   - Player cleanup
   - Resource management
   - Cache limits

2. **Network Optimization**
   - Adaptive quality
   - Preloading
   - Connection handling

## Integration Points

1. **Calendar Scheduling**
   - Event creation from video
   - Time slot selection
   - Google Calendar sync

2. **Second Brain**
   - Save/remove videos
   - Update counts
   - Manage metadata 