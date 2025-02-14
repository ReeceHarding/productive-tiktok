const {onObjectFinalized} = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
const ffmpeg = require("fluent-ffmpeg");
const {Storage} = require("@google-cloud/storage");
const axios = require("axios");
const fs = require("fs");
const path = require("path");
const os = require("os");
const FormData = require("form-data");

// Initialize the Admin SDK
admin.initializeApp();
const storage = new Storage();

// Ensure we have an API key
if (!process.env.OPENAI_API_KEY) {
  console.error("⚠️ OPENAI_API_KEY environment variable is not set");
}

/**
 * This function processes any uploaded file that appears to be a video.
 * It extracts audio, transcribes with Whisper, and uses GPT-4 for analysis.
 */
exports.processVideo = onObjectFinalized({
  timeoutSeconds: 540,
  memory: "2GB",
  region: "us-central1",
  secrets: ["OPENAI_API_KEY"]
}, async (event) => {
  const filePath = event.data.name;
  const fileName = path.basename(filePath);
  const fileExt = path.extname(fileName).toLowerCase();
  const videoId = path.basename(fileName, fileExt); // Remove any extension
  
  console.log(`🎥 Processing file: ${fileName} (ID: ${videoId})`);
  console.log(`📁 File path: ${filePath}`);
  console.log(`📎 File extension: ${fileExt}`);
  
  const bucket = storage.bucket(event.data.bucket);

  try {
    // Get the file metadata to find the uploader and verify it's a video
    const [metadata] = await bucket.file(filePath).getMetadata();
    console.log("📄 File metadata:", JSON.stringify(metadata, null, 2));
    
    // Check if it's a video file by content type
    const contentType = metadata.contentType || "";
    if (!contentType.startsWith("video/")) {
      console.log(`⏭️ Skipping non-video file (type: ${contentType})`);
      return;
    }
    
    const userId = metadata.metadata && metadata.metadata.userId;
    if (!userId) {
      console.log("⚠️ No userId in metadata, using 'anonymous'");
    }
    
    // Get user data if available
    let userData = {"username": "Anonymous User"};
    if (userId) {
      const userDoc = await admin.firestore().collection("users").doc(userId).get();
      if (userDoc.exists) {
        userData = userDoc.data();
      }
    }
    
    // Create/update video document
    const videoRef = admin.firestore().collection("videos").doc(videoId);
    
    // Initialize or update the video document
    await videoRef.set({
      id: videoId,
      ownerId: userId || "anonymous",
      ownerUsername: userData.username,
      videoURL: "",
      thumbnailURL: "",
      title: "Processing...",
      description: "Processing...",
      tags: [],
      processingStatus: "uploading",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      commentCount: 0,
      saveCount: 0,
      brainCount: 0,
      viewCount: 0,
      originalFileName: fileName,
      originalPath: filePath,
      contentType: contentType
    }, {merge: true});
    
    // If user exists, create user-video association
    if (userId) {
      await admin.firestore()
        .collection("users")
        .doc(userId)
        .collection("videos")
        .doc(videoId)
        .set({
          videoId,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        }, {merge: true});
    }

    // Generate a signed URL for the video
    console.log(`🔗 Generating signed URL for: ${filePath}`);
    const [signedUrl] = await bucket.file(filePath).getSignedUrl({
      action: "read",
      expires: "03-01-2500",
      version: "v4"
    });

    await videoRef.update({
      videoURL: signedUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Download video for processing
    console.log("⬇️ Downloading video for processing...");
    const tempFilePath = path.join(os.tmpdir(), fileName);
    await bucket.file(filePath).download({destination: tempFilePath});
    
    await videoRef.update({
      processingStatus: "transcribing",
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Extract audio (FFmpeg can handle various formats)
    const audioPath = path.join(os.tmpdir(), `${videoId}.mp3`);
    await new Promise((resolve, reject) => {
      ffmpeg(tempFilePath)
        .toFormat("mp3")
        .on("start", (cmd) => {
          console.log("🎵 FFmpeg command:", cmd);
        })
        .on("progress", (progress) => {
          console.log(`🎵 FFmpeg progress: ${JSON.stringify(progress)}`);
        })
        .on("end", () => {
          console.log("✅ Audio extraction complete");
          resolve();
        })
        .on("error", (error) => {
          console.error("❌ FFmpeg error:", error);
          reject(error);
        })
        .save(audioPath);
    });

    // 6) Transcribe audio with Whisper
    const formData = new FormData();
    formData.append("file", fs.createReadStream(audioPath));
    formData.append("model", "whisper-1");
    formData.append("response_format", "text");
    console.log("🗣️ Starting transcription with Whisper...");

    const response = await axios.post(
      "https://api.openai.com/v1/audio/transcriptions",
      formData,
      {
        headers: {
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`
        },
        maxBodyLength: Infinity
      }
    );
    const transcriptText = response.data;
    console.log("✅ Transcription completed");

    // Update Firestore with transcript
    await videoRef.update({
      transcript: transcriptText,
      processingStatus: "extracting_quotes",
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`✅ Updated doc with transcript for video ${videoId}`);

    // 7) Use GPT-4 to extract quotes
    try {
      console.log("🎯 Extracting quotes using GPT-4...");
      const chatPrompt = 
        "Extract 2-3 insightful quotes from the following video transcript for a second brain. " +
        "Format each quote on a new line starting with a dash (-). Keep them brief and meaningful.\n" +
        `Transcript:\n"${transcriptText}"`;

      const chatRes = await axios.post(
        "https://api.openai.com/v1/chat/completions",
        {
          model: "gpt-4",
          messages: [{role: "user", content: chatPrompt}],
          max_tokens: 150,
          temperature: 0.5
        },
        {
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`
          },
          maxBodyLength: Infinity
        }
      );
      
      console.log("✅ Received response from GPT-4 for quotes");
      const quoteText = chatRes.data.choices[0].message.content;
      const quotes = quoteText
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.startsWith("-"))
        .map((line) => line.substring(1).trim());
      
      console.log("📊 Extracted quotes:", quotes);

      // Update with quotes and move to metadata generation
      await videoRef.update({
        quotes,
        processingStatus: "generating_metadata",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`✅ Updated doc with quotes for video ${videoId}`);

      // 8) Generate additional metadata (title, description, 20 categories/tags)
      console.log("⚙️ Generating additional metadata with GPT-4...");
      const [titleRes, descriptionRes, tagsRes] = await Promise.all([
        // Title
        axios.post(
          "https://api.openai.com/v1/chat/completions",
          {
            model: "gpt-4",
            messages: [{
              role: "user",
              content:
                "Based on the following transcript, generate an engaging and catchy title " +
                "(max 60 characters):\n\n" + transcriptText
            }],
            max_tokens: 60,
            temperature: 0.7
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`
            }
          }
        ),
        // Description
        axios.post(
          "https://api.openai.com/v1/chat/completions",
          {
            model: "gpt-4",
            messages: [{
              role: "user",
              content:
                "Based on the following transcript, generate a concise and engaging video description " +
                "(max 200 characters):\n\n" + transcriptText
            }],
            max_tokens: 200,
            temperature: 0.7
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`
            }
          }
        ),
        // 20 tags
        axios.post(
          "https://api.openai.com/v1/chat/completions",
          {
            model: "gpt-4",
            messages: [{
              role: "user",
              content:
                "Read this transcript and produce 20 relevant category tags (comma-separated) " +
                "that best capture the main topics or themes:\n\n" + transcriptText
            }],
            max_tokens: 200,
            temperature: 0.7
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`
            }
          }
        )
      ]);

      const autoTitle = titleRes.data.choices[0].message.content.trim();
      const autoDescription = descriptionRes.data.choices[0].message.content.trim();
      const autoTags = tagsRes.data.choices[0].message.content.trim()
        .split(",")
        .map((tag) => tag.trim())
        .filter((tag) => tag);

      // Store final data
      console.log("✅ Generated metadata from GPT-4");
      console.log("Title:", autoTitle);
      console.log("Description:", autoDescription);
      console.log("Tags:", autoTags);

      await videoRef.update({
        autoTitle,
        title: autoTitle,
        autoDescription,
        description: autoDescription,
        autoTags,
        tags: autoTags,
        processingStatus: "ready",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`✅ Stored final metadata for video ${videoId}`);

      // Update secondBrain entries if they exist
      const secondBrainQuery = await admin
        .firestore()
        .collectionGroup("secondBrain")
        .where("videoId", "==", videoId)
        .get();
      
      if (!secondBrainQuery.empty) {
        const batch = admin.firestore().batch();
        secondBrainQuery.docs.forEach((doc) => {
          batch.update(doc.ref, {
            quotes,
            videoTitle: autoTitle,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        });
        await batch.commit();
        console.log(`✅ Updated ${secondBrainQuery.docs.length} secondBrain entries for video ${videoId}`);
      }

    } catch (contentErr) {
      console.error("Content generation failed:", contentErr);
      await videoRef.update({
        processingStatus: "error",
        processingError: "Failed to generate content: " + contentErr.message,
        transcript: transcriptText,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`❌ Updated video ${videoId} status=error`);
    }

    // Cleanup
    fs.unlinkSync(tempFilePath);
    fs.unlinkSync(audioPath);
    console.log("🧹 Cleaned up temporary files locally");

  } catch (error) {
    console.error("Error processing video:", error);
    // Mark as error in Firestore
    try {
      await admin.firestore().collection("videos").doc(videoId).update({
        processingStatus: "error",
        processingError: error.message || "Unknown error occurred",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`❌ Marked video ${videoId} as error with message: ${error.message}`);
    } catch (updateError) {
      console.error("Failed to update video doc after error:", updateError);
    }
  }
});