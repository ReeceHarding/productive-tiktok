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

  const bucket = storage.bucket(event.data.bucket);
  const videoId = path.basename(fileName, path.extname(fileName));

  try {
    // Update status to processing
    await admin.firestore().collection("videos").doc(videoId).update({
      processingStatus: "processing",
    });
    console.log(`Updated video ${videoId} status to processing`);

    // Download video to temp
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
      "The quotes should be brief and meaningful.\n" +
      `Transcript:\n"${transcriptText}"`;
    
    try {
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
        },
      );

      const quoteText = chatRes.data.choices[0].message.content;
      const quotes = quoteText.split("\n").filter((q) => q.trim());

      // Update video document with transcript, quotes and status
      await admin.firestore().collection("videos").doc(videoId).update({
        quotes: quotes,
        processingStatus: "ready",
      });
      console.log(`Updated video ${videoId} with quotes and status ready`);
    } catch (quoteErr) {
      console.error("Quote extraction failed:", quoteErr);
      // Even if quote extraction fails, we still have the transcript
      await admin.firestore().collection("videos").doc(videoId).update({
        quotes: [],
        processingStatus: "ready",
      });
      console.log(`Updated video ${videoId} status to ready (without quotes)`);
    }

    // Clean up temp files
    fs.unlinkSync(tempFilePath);
    fs.unlinkSync(audioPath);
    console.log("Cleaned up temporary files");
  } catch (error) {
    console.error("Error processing video:", error);
    // Update video status to error
    await admin.firestore().collection("videos").doc(videoId).update({
      processingStatus: "error",
    }).catch(console.error);
  }
});
