# SwingCoach Backend

Backend API for golf swing analysis using Cloudflare R2 storage.

## Setup

1. **Install Python dependencies:**
   ```bash
   cd backend
   python3 -m venv venv
   source venv/bin/activate  # On macOS/Linux
   pip install -r requirements.txt
   ```

2. **Configure R2 credentials:**
   ```bash
   cp .env.example .env
   # Edit .env and add your Cloudflare R2 credentials
   ```

   Get credentials from: https://dash.cloudflare.com → R2 → Manage R2 API Tokens

3. **Run the server:**
   ```bash
   python main.py
   # Or use uvicorn directly:
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

4. **Test the API:**
   ```bash
   # Health check
   curl http://localhost:8000/health
   
   # Get upload URL
   curl http://localhost:8000/upload-url
   ```

## API Endpoints

### `GET /health`
Health check - verifies R2 is configured.

### `GET /upload-url`
Returns a pre-signed URL for uploading a video to R2.

Response:
```json
{
  "upload_url": "https://...presigned-url...",
  "video_key": "swings/abc-123.mp4"
}
```

### `POST /analyze`
Analyzes a swing video that has been uploaded to R2.

Request:
```json
{
  "video_key": "swings/abc-123.mp4",
  "vantage": "DTL"
}
```

Response:
```json
{
  "summary": "Your swing shows early extension...",
  "metrics": {
    "Head Sway": "4.2 inches",
    "Hip Slide": "2.1 inches"
  },
  "drill_links": [
    {
      "title": "Fix Early Extension",
      "url": "https://youtube.com/...",
      "platform": "youtube"
    }
  ]
}
```

## Architecture

```
iOS App
  ↓
  1. GET /upload-url  →  Backend generates pre-signed URL
  ↓
  2. PUT <video>  →  Directly to R2 (not through backend)
  ↓
  3. POST /analyze  →  Backend downloads from R2, analyzes, returns results
```

## Project Structure

```
backend/
├── main.py          # FastAPI app and endpoints
├── models.py        # Pydantic schemas
├── r2_client.py     # Cloudflare R2 storage client
├── requirements.txt # Python dependencies
├── .env            # Configuration (not committed)
└── .env.example    # Template for .env
```

## Development

The server runs on `0.0.0.0:8000` by default. To connect from your iOS device:

1. Make sure your Mac and iPhone are on the same WiFi
2. Find your Mac's IP: `ipconfig getifaddr en0`
3. In your iOS app, use `http://<your-mac-ip>:8000`

## Next Steps

- [ ] Implement frame extraction (ffmpeg/opencv)
- [ ] Add pose detection (MediaPipe)
- [ ] Implement event detection
- [ ] Add DTL metrics calculation
- [ ] Build rule-based recommendation engine
