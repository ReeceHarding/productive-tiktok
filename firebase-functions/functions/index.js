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
    // Update status to processing
    await admin.firestore().collection("videos").doc(videoId).update({
      processingStatus: "processing",
    });
    console.log(`Updated video ${videoId} status to processing`);

    // Download video to temp for audio extraction
    const tempFilePath = path.join(os.tmpdir(), fileName);
    await bucket.file(filePath).download({destination: tempFilePath});
    console.log("Downloaded video to:", tempFilePath);

    // Extract audio for transcription (no video processing needed)
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

    // Update status to transcribing
    await admin.firestore().collection("videos").doc(videoId).update({
      processingStatus: "transcribing",
    });
    console.log(`Updated video ${videoId} status to transcribing`);

    // Call OpenAI Whisper API
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

    // Update status to extracting quotes
    await admin.firestore().collection("videos").doc(videoId).update({
      transcript: transcriptText,
      processingStatus: "extracting_quotes",
    });
    console.log(`Updated video ${videoId} with transcript and status extracting_quotes`);

    // Extract quotes using GPT-4
    const chatPrompt = 
      "Extract 2-3 insightful quotes from the following video transcript for a second brain. " +
      "Format each quote on a new line starting with a dash (-). The quotes should be brief and meaningful.\n" +
      `Transcript:\n"${transcriptText}"`;
    
    try {
      console.log("🎯 Sending quote extraction request to GPT-4...");
      console.log("📝 Transcript length:", transcriptText.length);
      
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
      console.log("📝 Raw quote text from GPT-4:", quoteText);
      
      // Parse quotes - look for lines starting with a dash
      const quotes = quoteText.split("\n")
        .map(line => line.trim())
        .filter(line => line.startsWith("-"))
        .map(line => line.substring(1).trim());
      
      console.log("📊 Extracted quotes:", quotes);
      console.log(`Found ${quotes.length} quotes`);

      if (quotes.length === 0) {
        console.warn("⚠️ No quotes were extracted from GPT-4 response");
        console.warn("GPT-4 raw response:", quoteText);
        throw new Error("Failed to extract any quotes from the transcript");
      }

      // Generate auto title first since we need it for updates
      console.log("Generating auto title...");
      const titlePrompt = 
        "Based on the following transcript, generate an engaging and catchy title " +
        "(max 60 characters):\n\n" + transcriptText;
      const titleRes = await axios.post(
        "https://api.openai.com/v1/chat/completions",
        {
          model: "gpt-4",
          messages: [{role: "user", content: titlePrompt}],
          max_tokens: 60,
          temperature: 0.7,
        },
        {
          headers: {
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
        }
      );
      const autoTitle = titleRes.data.choices[0].message.content.trim();
      console.log("Generated auto title:", autoTitle);

      // Update video document with quotes and metadata
      console.log("💾 Updating video document with quotes and metadata...");
      const videoUpdateData = {
        quotes: quotes,
        autoTitle: autoTitle,
        title: autoTitle, // Set both title fields
        processingStatus: "ready",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };
      
      await admin.firestore().collection("videos").doc(videoId).update(videoUpdateData);
      console.log(`✅ Successfully updated video ${videoId} with ${quotes.length} quotes`);

      // Update any existing Second Brain entries for this video
      const secondBrainQuery = await admin.firestore()
        .collectionGroup("secondBrain")
        .where("videoId", "==", videoId)
        .get();
      
      console.log(`Found ${secondBrainQuery.docs.length} Second Brain entries to update`);
      
      const batch = admin.firestore().batch();
      secondBrainQuery.docs.forEach(doc => {
        batch.update(doc.ref, {
          quotes: quotes,
          videoTitle: autoTitle,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });
      
      if (!secondBrainQuery.empty) {
        await batch.commit();
        console.log("✅ Updated all Second Brain entries with quotes");
      }

      // Generate auto description
      console.log("Generating auto description...");
      const descriptionPrompt = 
        "Based on the following transcript, generate a concise and engaging video description " +
        "(max 200 characters):\n\n" + transcriptText;
      const descriptionRes = await axios.post(
        "https://api.openai.com/v1/chat/completions",
        {
          model: "gpt-4",
          messages: [{role: "user", content: descriptionPrompt}],
          max_tokens: 200,
          temperature: 0.7,
        },
        {
          headers: {
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
        }
      );
      const autoDescription = descriptionRes.data.choices[0].message.content.trim();
      console.log("Generated auto description:", autoDescription);

      // Generate auto tags
      console.log("Generating auto tags...");
      const tagsPrompt = 
        "Based on the following transcript, generate 3-5 relevant tags " +
        "(comma-separated):\n\n" + transcriptText;
      const tagsRes = await axios.post(
        "https://api.openai.com/v1/chat/completions",
        {
          model: "gpt-4",
          messages: [{role: "user", content: tagsPrompt}],
          max_tokens: 100,
          temperature: 0.7,
        },
        {
          headers: {
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
        }
      );
      const tagsText = tagsRes.data.choices[0].message.content.trim();
      const autoTags = tagsText.split(",").map(tag => tag.trim()).filter(tag => tag);
      console.log("Generated auto tags:", autoTags);

      // Update video document with transcript, quotes, auto-generated content and status
      await admin.firestore().collection("videos").doc(videoId).update({
        quotes: quotes,
        autoTitle: autoTitle,
        autoDescription: autoDescription,
        autoTags: autoTags,
        processingStatus: "ready",
      });
      console.log(`Updated video ${videoId} with quotes, auto-generated content and status ready`);
    } catch (quoteErr) {
      console.error("Content generation failed:", quoteErr);
      // Even if content generation fails, we still have the transcript
      await admin.firestore().collection("videos").doc(videoId).update({
        quotes: [],
        processingStatus: "ready",
      });
      console.log(`Updated video ${videoId} status to ready (without generated content)`);
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
        processingStatus: "error",
        processingError: error.message || "Unknown error occurred"
      });
      console.log(`Updated video ${videoId} status to error`);
    } catch (updateError) {
      console.error("Failed to update error status:", updateError);
    }
  }
});
