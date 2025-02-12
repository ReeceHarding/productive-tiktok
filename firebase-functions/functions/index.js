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
  console.log(`Starting cloud function processing for video with ID: ${videoId}`);
  
  const bucket = storage.bucket(event.data.bucket);

  try {
    // 1) Mark Firestore doc as uploading (already done in the client)
    // 2) Generate a signed URL for the video
    console.log(`Generating signed URL for video: ${filePath}`);
    const signedUrlConfig = {
      action: "read",
      expires: "03-01-2500",
      version: "v4"
    };
    const [signedUrl] = await bucket.file(filePath).getSignedUrl(signedUrlConfig);
    console.log(`✅ Generated signed URL: ${signedUrl}`);

    // 3) Update Firestore with the signed URL
    await admin
      .firestore()
      .collection("videos")
      .doc(videoId)
      .update({
        videoURL: signedUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    console.log(`✅ Updated Firestore doc with signedURL for video ${videoId}`);

    // 4) Download the video to a temp folder so we can extract the audio
    console.log("Downloading video locally for audio extraction...");
    const tempFilePath = path.join(os.tmpdir(), fileName);
    await bucket.file(filePath).download({destination: tempFilePath});
    console.log("✅ Downloaded video locally:", tempFilePath);

    // *** At this point, we can set 'processingStatus' to 'transcribing' ***
    await admin
      .firestore()
      .collection("videos")
      .doc(videoId)
      .update({
        processingStatus: "transcribing",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    console.log(`🔄 Set processingStatus=transcribing for video ${videoId}`);

    // 5) Extract audio
    const audioPath = path.join(os.tmpdir(), `${videoId}.mp3`);
    await new Promise((resolve, reject) => {
      ffmpeg(tempFilePath)
        .toFormat("mp3")
        .on("end", () => {
          console.log("✅ Successfully extracted audio");
          resolve();
        })
        .on("error", (error) => {
          console.error("Error extracting audio:", error);
          reject(error);
        })
        .save(audioPath);
    });
    console.log("Extracted audio to:", audioPath);

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
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        maxBodyLength: Infinity,
      },
    );
    const transcriptText = response.data;
    console.log("✅ Transcription completed");

    // Update Firestore with transcript but keep status as transcribing
    await admin
      .firestore()
      .collection("videos")
      .doc(videoId)
      .update({
        transcript: transcriptText,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    console.log(`✅ Updated doc with transcript for video ${videoId} (still transcribing status)`);

    // *** Next, set 'processingStatus' to 'extracting_quotes' ***
    await admin
      .firestore()
      .collection("videos")
      .doc(videoId)
      .update({
        processingStatus: "extracting_quotes",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    console.log(`🔄 Set processingStatus=extracting_quotes for video ${videoId}`);

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
          temperature: 0.5,
        },
        {
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
          },
          maxBodyLength: Infinity,
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

      // *** Move to 'processingStatus' = 'generating_metadata' ***
      await admin
        .firestore()
        .collection("videos")
        .doc(videoId)
        .update({
          quotes: quotes,
          processingStatus: "generating_metadata",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      console.log(
        `✅ Updated doc with quotes and set status=generating_metadata for video ${videoId}`
      );

      // 8) Generate additional metadata (title, description, 20 categories/tags).
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
            temperature: 0.7,
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            },
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
            temperature: 0.7,
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            },
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
            temperature: 0.7,
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
            },
          }
        )
      ]);

      const autoTitle = titleRes.data.choices[0].message.content.trim();
      const autoDescription = descriptionRes.data.choices[0].message.content.trim();
      let autoTags = tagsRes.data.choices[0].message.content.trim()
        .split(",")
        .map((tag) => tag.trim())
        .filter((tag) => tag);

      // Log and store final data
      console.log("✅ Generated metadata from GPT-4");
      console.log("Title:", autoTitle);
      console.log("Description:", autoDescription);
      console.log("Tags:", autoTags);

      const finalUpdateData = {
        autoTitle,
        title: autoTitle,
        autoDescription,
        description: autoDescription,
        autoTags,
        tags: autoTags,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };

      await admin
        .firestore()
        .collection("videos")
        .doc(videoId)
        .update(finalUpdateData);
      console.log(`✅ Stored final metadata for video ${videoId}`);

      // *** Now set status to 'ready' ***
      await admin
        .firestore()
        .collection("videos")
        .doc(videoId)
        .update({
          processingStatus: "ready",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      console.log(`🎉 processingStatus=ready for video ${videoId}`);

      // Also update secondBrain entries if they exist
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
      // If quotes generation fails, set error and include transcript
      if (
        contentErr.message.includes("GPT-4") ||
        contentErr.message.includes("chat/completions")
      ) {
        await admin.firestore().collection("videos").doc(videoId).update({
          processingStatus: "error",
          processingError: "Failed to generate quotes: " + contentErr.message,
          transcript: transcriptText,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`Updated video ${videoId} status=error, saved transcript anyway`);
      } else {
        // For other errors in metadata generation, continue with ready status
        console.log(`Continuing with ready status for video ${videoId} despite metadata generation failure`);
      }
    }

    // Cleanup
    fs.unlinkSync(tempFilePath);
    fs.unlinkSync(audioPath);
    console.log("🧹 Cleaned up temporary files locally");

  } catch (error) {
    console.error("Error processing video:", error);
    // Mark as error
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