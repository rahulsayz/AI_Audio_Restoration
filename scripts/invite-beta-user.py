#!/usr/bin/env python3
"""
CLI tool to generate private, cryptographically signed invitation URLs for Sangeet AI beta users.
Saves invitations to a local SQLite tracking database.
"""

import sys
import os
import argparse
import sqlite3
from datetime import datetime, timedelta
import boto3
from botocore.config import Config

DB_PATH = "eval/reports/beta_invites.sqlite"
DEFAULT_BUCKET = "sangeet-builds-beta"
DEFAULT_KEY = "SangeetAI-1.0.0-Beta.dmg"

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS beta_invitations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL,
            bucket_name TEXT NOT NULL,
            object_key TEXT NOT NULL,
            presigned_url TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
        )
    """)
    conn.commit()
    conn.close()

def generate_presigned_url(bucket: str, key: str, expires_in_seconds: int) -> str:
    account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
    access_key = os.getenv("AWS_ACCESS_KEY_ID")
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
    
    if not (account_id and access_key and secret_key):
        print("Error: Missing Cloudflare S3 credentials.", file=sys.stderr)
        print("Please set the following environment variables:", file=sys.stderr)
        print("  CLOUDFLARE_ACCOUNT_ID", file=sys.stderr)
        print("  AWS_ACCESS_KEY_ID", file=sys.stderr)
        print("  AWS_SECRET_ACCESS_KEY", file=sys.stderr)
        sys.exit(1)
        
    endpoint_url = f"https://{account_id}.r2.cloudflarestorage.com"
    
    # Configure boto3 to use signature version v4
    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4")
    )
    
    try:
        url = s3.generate_presigned_url(
            ClientMethod="get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=expires_in_seconds
        )
        return url
    except Exception as e:
        print(f"Error generating presigned URL from Cloudflare R2: {e}", file=sys.stderr)
        sys.exit(1)

def save_invitation(email: str, bucket: str, key: str, url: str, expires_delta: timedelta):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    created_at = datetime.utcnow().isoformat()
    expires_at = (datetime.utcnow() + expires_delta).isoformat()
    
    # Mark old active invites for this email as inactive
    cursor.execute(
        "UPDATE beta_invitations SET is_active = 0 WHERE email = ? AND is_active = 1",
        (email,)
    )
    
    cursor.execute("""
        INSERT INTO beta_invitations (email, bucket_name, object_key, presigned_url, created_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (email, bucket, key, url, created_at, expires_at))
    
    conn.commit()
    conn.close()

def main():
    parser = argparse.ArgumentParser(
        description="Generate private, 7-day presigned invitation URLs for Sangeet AI beta testers."
    )
    parser.add_argument("email", help="Email address of the beta tester")
    parser.add_argument(
        "--bucket", 
        default=os.getenv("BETA_BUCKET_NAME", DEFAULT_BUCKET),
        help=f"R2 bucket name (default: {DEFAULT_BUCKET})"
    )
    parser.add_argument(
        "--key", 
        default=DEFAULT_KEY,
        help=f"S3 object key to presign (default: {DEFAULT_KEY})"
    )
    parser.add_argument(
        "--days", 
        type=int, 
        default=7, 
        help="Number of days the URL should remain active (default: 7)"
    )
    args = parser.parse_args()
    
    init_db()
    
    expires_in_seconds = args.days * 86400
    
    print(f"Generating presigned R2 download link for {args.email}...")
    url = generate_presigned_url(args.bucket, args.key, expires_in_seconds)
    
    save_invitation(args.email, args.bucket, args.key, url, timedelta(days=args.days))
    
    print("\n" + "="*80)
    print("SANGEET AI BETA INVITATION GENERATED")
    print("="*80)
    print(f"Tester Email:  {args.email}")
    print(f"Expiry Period: {args.days} Days")
    print(f"R2 Target:     s3://{args.bucket}/{args.key}")
    print(f"Invite URL:\n\n{url}\n")
    print("="*80)
    print("Local sqlite record stored successfully.")

if __name__ == "__main__":
    main()
