#!/usr/bin/env python3
"""Disposable local storage adapter for exercising the production analysis API.

Run only through verify-coaching.sh. No R2 or model requests leave this process.
Pose detection, metrics, rendering, async runs and response assembly are real.
"""
import argparse
import os
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["OPENAI_API_KEY"] = ""
from fastapi import HTTPException, Request
from fastapi.responses import FileResponse
import uvicorn
import main
from analysis.pipeline_3d import SwingCoachPipeline3D


def build_app(storage, port):
    storage.mkdir(parents=True, exist_ok=True)

    class LocalStorage:
        def path(self, key):
            path = (storage / key).resolve()
            if not path.is_relative_to(storage.resolve()):
                raise HTTPException(400, "Invalid key")
            return path

        def generate_upload_url(self):
            key = f"uploads/{uuid.uuid4().hex}.mp4"
            return {"upload_url": self.generate_download_url(key), "video_key": key}

        def generate_download_url(self, key):
            return f"http://127.0.0.1:{port}/verification-assets/{key}"

        def video_exists(self, key):
            return self.path(key).is_file()

        def download_video(self, key):
            return self.path(key).read_bytes()

        def upload_bytes(self, key, data, content_type=None):
            path = self.path(key)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

        upload_video = upload_bytes

    local = LocalStorage()
    main.get_r2_client = lambda: local
    main._pipeline = SwingCoachPipeline3D(output_root=storage / "runs")

    @main.app.get("/verification-ready")
    async def ready():
        return {"pid": os.getpid(), "storage": str(storage)}

    @main.app.put("/verification-assets/{key:path}")
    async def upload(key: str, request: Request):
        local.upload_bytes(key, await request.body())
        return {"saved": key}

    @main.app.get("/verification-assets/{key:path}")
    async def download(key: str):
        if not local.video_exists(key):
            raise HTTPException(404)
        return FileResponse(local.path(key))

    return main.app


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--storage", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8871)
    args = parser.parse_args()
    uvicorn.run(build_app(args.storage, args.port), host="127.0.0.1", port=args.port)
