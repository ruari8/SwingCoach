"""
Cloudflare R2 storage client.
Handles video upload/download using S3-compatible API.
"""

import os
import uuid
import boto3
from typing import Optional
from dotenv import load_dotenv

load_dotenv()


class R2Client:
    """Client for interacting with Cloudflare R2 storage."""
    
    def __init__(self):
        self.account_id = os.getenv("R2_ACCOUNT_ID")
        self.access_key = os.getenv("R2_ACCESS_KEY_ID")
        self.secret_key = os.getenv("R2_SECRET_ACCESS_KEY")
        self.bucket_name = os.getenv("R2_BUCKET_NAME", "swing-coach")
        
        if not all([self.account_id, self.access_key, self.secret_key]):
            raise ValueError("R2 credentials not configured. Check .env file.")
        
        # R2 endpoint format
        endpoint_url = f"https://{self.account_id}.r2.cloudflarestorage.com"
        
        # Create S3 client configured for R2
        self.s3 = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            region_name='auto'  # R2 uses 'auto' for region
        )
    
    def generate_upload_url(self, video_key: Optional[str] = None, expiration: int = 3600) -> dict:
        """
        Generate a pre-signed URL for uploading a video to R2.
        
        Args:
            video_key: Optional custom key. If not provided, generates UUID-based key.
            expiration: URL expiration time in seconds (default: 1 hour)
        
        Returns:
            Dict with 'upload_url' and 'video_key'
        """
        if not video_key:
            video_key = f"swings/{uuid.uuid4()}.mp4"
        
        # Generate pre-signed PUT URL
        upload_url = self.s3.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': self.bucket_name,
                'Key': video_key,
                'ContentType': 'video/mp4'
            },
            ExpiresIn=expiration
        )
        
        return {
            "upload_url": upload_url,
            "video_key": video_key
        }
    
    def download_video(self, video_key: str) -> bytes:
        """
        Download video bytes from R2.
        
        Args:
            video_key: The key of the video to download
        
        Returns:
            Video file contents as bytes
        """
        response = self.s3.get_object(Bucket=self.bucket_name, Key=video_key)
        return response['Body'].read()
    
    def delete_video(self, video_key: str) -> None:
        """
        Delete a video from R2.
        
        Args:
            video_key: The key of the video to delete
        """
        self.s3.delete_object(Bucket=self.bucket_name, Key=video_key)
    
    def video_exists(self, video_key: str) -> bool:
        """
        Check if a video exists in R2.
        
        Args:
            video_key: The key to check
        
        Returns:
            True if video exists, False otherwise
        """
        try:
            self.s3.head_object(Bucket=self.bucket_name, Key=video_key)
            return True
        except:
            return False


# Singleton instance
_r2_client: Optional[R2Client] = None


def get_r2_client() -> R2Client:
    """Get or create the R2 client singleton."""
    global _r2_client
    if _r2_client is None:
        _r2_client = R2Client()
    return _r2_client
