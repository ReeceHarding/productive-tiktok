/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {onObjectFinalized} = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
const ffmpeg = require("fluent-ffmpeg");
const {Storage} = require("@google-cloud/storage");
const axios = require("axios");
const fs = require("fs");
const path = require("path");
const os = require("os");
const FormData = require("form-data");

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

// Initialize the Admin SDK
admin.initializeApp();
const storage = new Storage();

// Ensure we have an API key
if (!process.env.OPENAI_API_KEY) {
  console.error("⚠️ OPENAI_API_KEY environment variable is not set");
}

/**
 * This function runs when a file in Cloud Storage (under 'videos/' folder) is finalized.
 * It processes the video, extracts audio, transcribes with Whisper, and then uses GPT-4
 * to extract quotes, generate metadata (title, description, tags, etc.).
 * Finally, it updates Firestore with the final data for the video in 'videos/{videoId}'.
 */
exports.processVideo = onObjectFinalized({
  timeoutSeconds: 540,
  memory: "2GB",
  region: "us-central1",
  secrets: ["OPENAI_API_KEY"]
}, async (event) => {
  const filePath = event.data.name;
  const fileName = path.basename(filePath);
  
  // Only process videos in the videos/ folder
  if (!filePath.startsWith("videos/")) {
    console.log("Not a video upload, skipping processing");
    return;
  }
  
  // Extract videoId from the filename (remove .mp4 extension)
  const videoId = path.basename(fileName, ".mp4");
  console.log(`Processing video with ID: ${videoId}`);
  
  const bucket = storage.bucket(event.data.bucket);
  
  try {
    console.log(`Starting processing for video ${videoId} (status: uploading)`);
    
    // Generate a signed URL for the video with a long expiration
    const signedUrlConfig = {
      action: 'read',
      expires: '03-01-2500', // Very long expiration
      version: 'v4'
    };
    
    console.log(`Generating signed URL for video: ${filePath}`);
    const [signedUrl] = await bucket.file(filePath).getSignedUrl(signedUrlConfig);
    console.log(`✅ Generated signed URL: ${signedUrl}`);
    
    // Update Firestore doc with signedURL but keep status as uploading
    await admin.firestore().collection("videos").doc(videoId).update({
      videoURL: signedUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`✅ Updated video document with signed URL (status: uploading)`);

    // Download video to temp to extract audio
    const tempFilePath = path.join(os.tmpdir(), fileName);
    await bucket.file(filePath).download({destination: tempFilePath});
    console.log("Downloaded video to:", tempFilePath);
    
    // Extract audio
    const audioPath = path.join(os.tmpdir(), `${videoId}.mp3`);
    await new Promise((resolve, reject) => {
      ffmpeg(tempFilePath)
        .toFormat("mp3")
        .on("end", () => {
          console.log("Successfully extracted audio");
          resolve();
        })
        .on("error", (error) => {
          console.error("Error extracting audio:", error);
          reject(error);
        })
        .save(audioPath);
    });
    console.log("Extracted audio to:", audioPath);
    
    // Whisper transcription
    const formData = new FormData();
    formData.append("file", fs.createReadStream(audioPath));
    formData.append("model", "whisper-1");
    formData.append("response_format", "text");
    
    const response = await axios.post(
      "https://api.openai.com/v1/audio/transcriptions",
      formData,
      {
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        maxBodyLength: Infinity,
      },
    );
    
    const transcriptText = response.data;
    console.log("✅ Transcription completed");
    
    // Update with transcript but keep status as uploading
    await admin.firestore().collection("videos").doc(videoId).update({
      transcript: transcriptText,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`✅ Updated video ${videoId} with transcript (status: uploading)`);
    
    // GPT-4: Extract quotes
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
          temperature: 0.5,
        },
        {
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
          },
          maxBodyLength: Infinity,
        },
      );
      
      console.log("✅ Received response from GPT-4 for quotes");
      const quoteText = chatRes.data.choices[0].message.content;
      const quotes = quoteText
        .split("\n")
        .map(line => line.trim())
        .filter(line => line.startsWith("-"))
        .map(line => line.substring(1).trim());
      
      console.log("📊 Extracted quotes:", quotes);
      
      // Update to ready status with transcript and quotes
      await admin.firestore().collection("videos").doc(videoId).update({
        transcript: transcriptText,
        quotes: quotes,
        processingStatus: "ready", 
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`✅ Updated video ${videoId} to ready status with transcript and quotes`);
      
      // Next: Generate additional metadata (title, description, 20 categories/tags).
      console.log("Generating additional metadata...");
      const [titleRes, descriptionRes, tagsRes] = await Promise.all([
        // Title generation
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
            temperature: 0.7,
          },
          {
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            },
          }
        ),
        // Description generation
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
            temperature: 0.7,
          },
          {
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            },
          }
        ),
        // 20 Categories (Tags) generation
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
            temperature: 0.7,
          },
          {
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            },
          }
        )
      ]);
      
      const autoTitle = titleRes.data.choices[0].message.content.trim();
      const autoDescription = descriptionRes.data.choices[0].message.content.trim();
      let autoTags = tagsRes.data.choices[0].message.content.trim()
        .split(",")
        .map(tag => tag.trim())
        .filter(tag => tag);
      
      // If for any reason we don't see 20 tags, let's allow it but we'll log the actual count
      console.log("✅ Generated metadata");
      console.log("Title:", autoTitle);
      console.log("Description:", autoDescription);
      console.log("Tags:", autoTags);
      
      const finalUpdateData = {
        autoTitle: autoTitle,
        title: autoTitle,
        autoDescription: autoDescription,
        description: autoDescription,
        autoTags: autoTags,
        tags: autoTags,  // Also store final tags as tags
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };
      
      // Final update with everything
      await admin.firestore().collection("videos").doc(videoId).update(finalUpdateData);
      console.log(`✅ Successfully updated video ${videoId} with additional metadata (20 categories/tags)`);
      
      // Also update secondBrain entries if they exist
      const secondBrainQuery = await admin.firestore()
        .collectionGroup("secondBrain")
        .where("videoId", "==", videoId)
        .get();
      
      if (!secondBrainQuery.empty) {
        const batch = admin.firestore().batch();
        secondBrainQuery.docs.forEach(doc => {
          batch.update(doc.ref, {
            quotes: quotes,
            videoTitle: autoTitle,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        });
        await batch.commit();
        console.log(`✅ Updated ${secondBrainQuery.docs.length} secondBrain entries for video ${videoId}`);
      }
      
    } catch (contentErr) {
      console.error("Content generation failed:", contentErr);
      // If quotes generation fails, set error and include transcript
      if (contentErr.message.includes("GPT-4") || contentErr.message.includes("chat/completions")) {
        await admin.firestore().collection("videos").doc(videoId).update({
          processingStatus: "error",
          processingError: "Failed to generate quotes: " + contentErr.message,
          transcript: transcriptText,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`Updated video ${videoId} status to error but saved transcript`);
      } else {
        // For other errors in metadata generation, continue with ready status
        console.log(`Continuing with ready status for video ${videoId} despite metadata generation failure`);
      }
    }
    
    // Cleanup
    fs.unlinkSync(tempFilePath);
    fs.unlinkSync(audioPath);
    console.log("Cleaned up temporary files");
    
  } catch (error) {
    console.error("Error processing video:", error);
    // Update video status to error
    try {
      await admin.firestore().collection("videos").doc(videoId).update({
        processingStatus: "error",
        processingError: error.message || "Unknown error occurred",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`Updated video ${videoId} status to error`);
    } catch (updateError) {
      console.error("Failed to update error status:", updateError);
    }
  }
});
