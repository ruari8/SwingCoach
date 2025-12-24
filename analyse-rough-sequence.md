┌─────────────────────────────────────────────────────────────────────────────┐
│                           iOS APP                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. User selects swing → you have photoAssetID                              │
│                          ↓                                                  │
│  2. Fetch video from Photos library                                         │
│     PHAsset → AVAsset → export to temp .mp4 file                            │
│                          ↓                                                  │
│  3. Request upload URL from backend                                         │
│     GET /upload-url?swing_id=abc123                                         │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BACKEND                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  4. Generate pre-signed URL for R2                                          │
│     s3.generate_presigned_url('put_object', ...)                            │
│                          ↓                                                  │
│  5. Return URL to app                                                       │
│     { "upload_url": "https://xxx.r2.cloudflarestorage.com/...",             │
│       "video_key": "swings/abc123.mp4" }                                    │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           iOS APP (continued)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  6. Upload video DIRECTLY to R2 (not to your backend!)                      │
│     PUT https://xxx.r2.cloudflarestorage.com/swings/abc123.mp4              │
│     Body: <video bytes>                                                     │
│                          ↓                                                  │
│  7. Tell backend "video is ready, analyze it"                               │
│     POST /analyze                                                           │
│     { "video_key": "swings/abc123.mp4", "vantage": "DTL" }                  │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BACKEND (analysis)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  8. Download video from R2                                                  │
│     s3.get_object(Bucket='swingcoach', Key='swings/abc123.mp4')             │
│                          ↓                                                  │
│  9. Extract frames (ffmpeg)                                                 │
│                          ↓                                                  │
│  10. Run pose detection (MediaPipe)                                         │
│                          ↓                                                  │
│  11. Detect events (address, top, impact)                                   │
│                          ↓                                                  │
│  12. Calculate metrics (head sway, etc.)                                    │
│                          ↓                                                  │
│  13. Map metrics → drills (rule engine)                                     │
│                          ↓                                                  │
│  14. Return JSON response                                                   │
│      {                                                                      │
│        "summary": "Early extension with head sway",                         │
│        "metrics": { "head_sway": 4.2, ... },                                │
│        "drills": [...]                                                      │
│      }                                                                      │
│                                                                             │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           iOS APP (final)                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  15. Receive response, update UI                                            │
│      Display metrics, drills, etc.                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘