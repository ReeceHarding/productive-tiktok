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

// Constants for URL signing
const SECONDS_IN_DAY = 86400;
const EXPIRATION_DAYS = 6; // Using 6 days instead of 7 for safety margin

/**
 * Generates a unique video ID based on filename and timestamp
 * @param {string} filename The original filename
 * @returns {string} A unique video ID
 */
function generateVideoId(filename) {
  // Extract the video ID from the filename (it's already in the format we want)
  const videoId = path.basename(filename, path.extname(filename));
  console.log(`🔑 Using existing video ID from filename: ${videoId}`);
  return videoId;
}

/**
 * Validates that a file is a video by checking its content type
 * @param {Storage.Bucket} bucket The storage bucket
 * @param {string} filePath The path to the file
 * @returns {Promise<{isValid: boolean, metadata: object}>}
 */
async function validateVideoFile(bucket, filePath) {
  try {
    const [metadata] = await bucket.file(filePath).getMetadata();
    const contentType = metadata.contentType || "";
    const isVideo = contentType.startsWith("video/");
    
    if (!isVideo) {
      console.error(`❌ Invalid content type: ${contentType}. Expected video/*`);
      return {isValid: false, metadata};
    }

    console.log(`✅ Validated video file: ${filePath}`);
    console.log(`📊 Content Type: ${contentType}`);
    console.log(`📊 Size: ${metadata.size} bytes`);
    console.log(`📊 Created: ${metadata.timeCreated}`);
    
    return {isValid: true, metadata};
  } catch (error) {
    console.error(`❌ Failed to validate video file: ${filePath}`, error);
    return {isValid: false, metadata: null};
  }
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
  
  const bucket = storage.bucket(event.data.bucket);
  let videoId;
  let tempFilePath;
  let audioPath;

  try {
    // Validate the video file first
    const {isValid, metadata} = await validateVideoFile(bucket, filePath);
    if (!isValid) {
      console.error("❌ File validation failed - not a valid video file");
      return;
    }

    // Generate a unique video ID
    videoId = generateVideoId(fileName);
    console.log(`✅ Processing video with ID: ${videoId}`);
    
    // Create initial Firestore document
    await admin
      .firestore()
      .collection("videos")
      .doc(videoId)
      .set({
        originalFileName: fileName,
        contentType: metadata.contentType,
        size: metadata.size,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        processingStatus: "uploading"
      });
    console.log(`✅ Created initial Firestore document for video ${videoId}`);

    // Generate a signed URL for the video
    console.log(`Generating signed URL for video: ${filePath}`);
    const expirationTime = Date.now() + (SECONDS_IN_DAY * EXPIRATION_DAYS * 1000);
    const signedUrlConfig = {
      action: "read",
      expires: expirationTime,
      version: "v4"
    };
    console.log(`🕒 Generating signed URL with ${EXPIRATION_DAYS} days expiration`);
    const [signedUrl] = await bucket.file(filePath).getSignedUrl(signedUrlConfig);
    console.log(`✅ Generated signed URL: ${signedUrl}`);

    // Update Firestore with the signed URL and its expiration
    await admin
      .firestore()
      .collection("videos")
      .doc(videoId)
      .update({
        videoURL: signedUrl,
        videoURLExpiration: admin.firestore.Timestamp.fromMillis(expirationTime),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    console.log(`✅ Updated Firestore doc with signedURL and expiration for video ${videoId}`);

    // Download the video to a temp folder so we can extract the audio
    console.log("Downloading video locally for audio extraction...");
    tempFilePath = path.join(os.tmpdir(), fileName);
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
    audioPath = path.join(os.tmpdir(), `${videoId}.mp3`);
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

    // Get headers from FormData including the correct Content-Type with boundary
    const formHeaders = formData.getHeaders();

    const response = await axios.post(
      "https://api.openai.com/v1/audio/transcriptions",
      formData,
      {
        headers: {
          ...formHeaders,
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
      try {
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
      } catch (secondBrainError) {
        // Log the error but don't throw - this is a non-critical update
        console.log(
          `⚠️ Could not update secondBrain entries: ${secondBrainError.message}. ` +
          "This is expected if the collection group index is not set up."
        );
      }

      console.log(`✨ All processing completed successfully for video ${videoId}`);

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

  } catch (error) {
    console.error("Error processing video:", error);
    // Mark as error if we have a videoId
    if (videoId) {
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
    } else {
      console.error("Could not update error status - no valid videoId");
    }
  } finally {
    // Cleanup temporary files if they exist
    try {
      if (tempFilePath && fs.existsSync(tempFilePath)) {
        fs.unlinkSync(tempFilePath);
      }
      if (audioPath && fs.existsSync(audioPath)) {
        fs.unlinkSync(audioPath);
      }
      console.log("🧹 Cleaned up temporary files locally");
    } catch (cleanupError) {
      console.error("Error during cleanup:", cleanupError);
    }
  }
});