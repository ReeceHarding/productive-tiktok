# Reimagined Video Streaming Approach

## Introduction
This doc outlines a from-first-principles approach to improve our existing video streaming and playback to more closely resemble a TikTok-style feed. While our current approach streams MP4 files from Firebase Storage, we can consider new methods to enhance performance, reduce load time, and optimize for short-form vertical videos.

---

## 1. Using HLS or DASH for Adaptive Streaming
- **Background**: TikTok typically delivers short videos quickly and seamlessly, allowing instant playback as soon as the user swipes to the next video. One way is to serve the videos in an adaptive streaming format like HLS (HTTP Live Streaming) or DASH.
- **Reasoning**:
  - Allows chunk-based loading of video segments.
  - Adapts video quality automatically to the user's network conditions.
  - Lowers stall rates by buffering small segments at a time rather than a single large MP4.
- **Implementation**:
  1. Convert each MP4 to HLS (M3U8 playlist + TS segments or fMP4).
  2. Upload the HLS segments and master playlist to Firebase Storage.
  3. Update the `videoURL` in Firestore to point to the `.m3u8` file instead of a full MP4.

## 2. Prefetching & Smooth Scrolling
- **Background**: As the user scrolls up or down, new videos start to preload. Our existing approach does partial preloading of MP4. With short videos, we can do a deeper prefetch using HLS segments.
- **Reasoning**:
  - By preloading the next video's earliest segments, a new video can be presented without abrupt waiting.
  - Minimizes perceived buffering if the user swipes quickly.
- **Implementation**:
  1. For each video in the feed, request the first segment(s) if user is within some range of that video in the list.
  2. Integrate logic to skip or stop prefetching once user moves far away from that upcoming content.

## 3. Scalable Comments & Engagement
- We keep the same Firestore-based structure:
  - `videos/<videoId>/comments/...`
- But we can unify user engagement flows with typical short video patterns:
  - **Double-tap** for "like" or saving to second brain.
  - **Brain icon** for second brain and transcripts.
  - **Comment button** slides up a sheet. Within that sheet, instruct: "Click the brain icon next to a comment to add it to your second brain."

## 4. Vertical Feed & UI Controls
- Our approach remains a "swipe up" or "TabView with .pageTabViewStyle()" for quick transitions, but we can refine:
  - Use a custom "paging" scroll like SwiftUI's `ScrollViewReader` or a UIPageViewController approach for more direct control over transitions and preloading.

## 5. Potential Cloud Functions / Microservices
- We keep the existing `processVideo` function but extend it to handle HLS packaging. 
  - Tools: [FFmpeg's segmenting approach](https://ffmpeg.org/ffmpeg.html#Main-options) or [AWS MediaConvert-like services], though for Firebase we can do it in Cloud Run or a CF environment with sufficient memory.

## 6. Conclusion
This approach better mimics the typical "TikTok feel" with instant playback, adaptive streaming, and advanced prefetching. It still respects our existing Firestore schema, second brain integration, and overall concept. By migrating from a single MP4 to a modern chunked approach, we reduce stalling, improve load times, and create a fluid user experience. 