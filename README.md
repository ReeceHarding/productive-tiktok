# Productive TikTok

A TikTok-style video sharing app focused on productivity and learning, built with SwiftUI and Firebase.

## Features

- Short-form vertical video sharing
- AI-powered quote extraction
- Second Brain functionality for saving insights
- Social features (likes, comments, shares)
- User profiles and authentication
- Real-time video processing
- Smart content tagging

## Tech Stack

- SwiftUI for UI
- Firebase (Auth, Firestore, Storage, Functions)
- OpenAI GPT-4 for quote extraction
- AVKit for video playback
- Combine for reactive programming

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Firebase project with necessary services enabled
- OpenAI API key for quote extraction

## Installation

1. Clone the repository
```bash
git clone https://github.com/ReeceHarding/productive-tiktok.git
```

2. Install dependencies via Swift Package Manager
```bash
xcodebuild -resolvePackageDependencies
```

3. Add your `GoogleService-Info.plist` to the project

4. Set up Firebase Cloud Functions
```bash
cd firebase-functions
npm install
firebase deploy --only functions
```

5. Configure environment variables in Firebase Functions
- Add OpenAI API key to Firebase Functions secrets

## Architecture

- MVVM architecture
- Protocol-oriented programming
- Dependency injection
- Clean architecture principles
- Modular design

## Features in Detail

### Video Processing Pipeline
1. Video upload
2. Server-side processing
3. Transcription via Whisper API
4. Quote extraction via GPT-4
5. Thumbnail generation

### Second Brain
- Save insightful quotes
- Organize by topics
- Daily insights
- Search functionality

### Social Features
- Like/Comment system
- Share functionality
- User profiles
- Activity feed

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Contact

Reece Harding - [@YourTwitter](https://twitter.com/YourTwitter)

Project Link: [https://github.com/ReeceHarding/productive-tiktok](https://github.com/ReeceHarding/productive-tiktok) 