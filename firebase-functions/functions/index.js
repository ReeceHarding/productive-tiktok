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

admin.initializeApp();
const storage = new Storage();

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
  
  // Extract the video ID from the filename (remove .mp4 extension)
  const videoId = path.basename(fileName, ".mp4");
  console.log(`Processing video with ID: ${videoId}`);
  
  const bucket = storage.bucket(event.data.bucket);
  
  try {
    // Keep status as "uploading" while we process
    // This matches our Swift enum: case uploading = "uploading"
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
    
    // Update video document with signed URL but keep status as uploading
    await admin.firestore().collection("videos").doc(videoId).update({
      videoURL: signedUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`✅ Updated video document with signed URL (status: uploading)`);

    // Download video to temp for audio extraction
    const tempFilePath = path.join(os.tmpdir(), fileName);
    await bucket.file(filePath).download({destination: tempFilePath});
    console.log("Downloaded video to:", tempFilePath);
    
    // Extract audio for transcription
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
    
    // Call OpenAI Whisper API for transcription
    const formData = new FormData();
    formData.append("file", fs.createReadStream(audioPath));
    formData.append("model", "whisper-1");
    formData.append("response_format", "text");
    
    const response = await axios.post(
      "https://api.openai.com/v1/audio/transcriptions",
      formData,
      {
        headers: {
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
          ...formData.getHeaders(),
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
    
    try {
      console.log("🎯 Extracting quotes using GPT-4...");
      const chatPrompt = 
        "Extract 2-3 insightful quotes from the following video transcript for a second brain. " +
        "Format each quote on a new line starting with a dash (-). The quotes should be brief and meaningful.\n" +
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
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
          maxBodyLength: Infinity,
        },
      );
      
      console.log("✅ Received response from GPT-4");
      const quoteText = chatRes.data.choices[0].message.content;
      const quotes = quoteText.split("\n")
        .map(line => line.trim())
        .filter(line => line.startsWith("-"))
        .map(line => line.substring(1).trim());
      
      console.log("📊 Extracted quotes:", quotes);
      
      // Update to ready status with transcript and quotes immediately
      await admin.firestore().collection("videos").doc(videoId).update({
        transcript: transcriptText,
        quotes: quotes,
        processingStatus: "ready", // This matches our Swift enum: case ready = "ready"
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`✅ Updated video ${videoId} to ready status with transcript and quotes`);
      
      // Generate additional metadata in the background
      console.log("Generating additional metadata...");
      const [titleRes, descriptionRes, tagsRes] = await Promise.all([
        // Title generation
        axios.post(
          "https://api.openai.com/v1/chat/completions",
          {
            model: "gpt-4",
            messages: [{role: "user", content: 
              "Based on the following transcript, generate an engaging and catchy title " +
              "(max 60 characters):\n\n" + transcriptText
            }],
            max_tokens: 60,
            temperature: 0.7,
          },
          {
            headers: {
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
              "Content-Type": "application/json",
            },
          }
        ),
        // Description generation
        axios.post(
          "https://api.openai.com/v1/chat/completions",
          {
            model: "gpt-4",
            messages: [{role: "user", content:
              "Based on the following transcript, generate a concise and engaging video description " +
              "(max 200 characters):\n\n" + transcriptText
            }],
            max_tokens: 200,
            temperature: 0.7,
          },
          {
            headers: {
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
              "Content-Type": "application/json",
            },
          }
        ),
        // Tags generation
        axios.post(
          "https://api.openai.com/v1/chat/completions",
          {
            model: "gpt-4",
            messages: [{role: "user", content:
              "Based on the following transcript, generate 3-5 relevant tags " +
              "(comma-separated):\n\n" + transcriptText
            }],
            max_tokens: 100,
            temperature: 0.7,
          },
          {
            headers: {
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
              "Content-Type": "application/json",
            },
          }
        )
      ]);
      
      const autoTitle = titleRes.data.choices[0].message.content.trim();
      const autoDescription = descriptionRes.data.choices[0].message.content.trim();
      const autoTags = tagsRes.data.choices[0].message.content.trim()
        .split(",").map(tag => tag.trim()).filter(tag => tag);
      
      console.log("✅ Generated metadata");
      console.log("Title:", autoTitle);
      console.log("Description:", autoDescription);
      console.log("Tags:", autoTags);
      
      // Final update with all content and ready status
      const finalUpdateData = {
        autoTitle: autoTitle,
        title: autoTitle,
        autoDescription: autoDescription,
        description: autoDescription,
        autoTags: autoTags,
        tags: autoTags,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };
      
      await admin.firestore().collection("videos").doc(videoId).update(finalUpdateData);
      console.log(`✅ Successfully updated video ${videoId} with additional metadata`);
      
      // Update Second Brain entries if they exist
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
        console.log(`✅ Updated ${secondBrainQuery.docs.length} Second Brain entries`);
      }
      
    } catch (contentErr) {
      console.error("Content generation failed:", contentErr);
      // If quotes generation fails, set error and include transcript
      if (contentErr.message.includes("GPT-4") || contentErr.message.includes("chat/completions")) {
        await admin.firestore().collection("videos").doc(videoId).update({
          processingStatus: "error", // This matches our Swift enum: case error = "error"
          processingError: "Failed to generate quotes: " + contentErr.message,
          transcript: transcriptText, // Still save the transcript even if quotes fail
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`Updated video ${videoId} status to error but saved transcript`);
      } else {
        // For other errors in metadata generation, continue with ready status
        console.log(`Continuing with ready status for video ${videoId} despite metadata generation failure`);
      }
    }
    
    // Clean up temp files
    fs.unlinkSync(tempFilePath);
    fs.unlinkSync(audioPath);
    console.log("Cleaned up temporary files");
    
  } catch (error) {
    console.error("Error processing video:", error);
    // Update video status to error
    try {
      await admin.firestore().collection("videos").doc(videoId).update({
        processingStatus: "error", // This matches our Swift enum: case error = "error"
        processingError: error.message || "Unknown error occurred",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`Updated video ${videoId} status to error`);
    } catch (updateError) {
      console.error("Failed to update error status:", updateError);
    }
  }
});
