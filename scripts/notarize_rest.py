#!/usr/bin/env python3
"""
Notarize a DMG using Apple's Notary REST API directly.
Avoids xcrun notarytool dependency. Uses webhook-free polling.

Usage:
  python3 scripts/notarize_rest.py \
    --key AuthKey_XXXXXXXXXX.p8 \
    --key-id XXXXXXXXXX \
    --issuer-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
    --file build/YapYap-v0.2.0.dmg

Requirements:
  pip3 install pyjwt boto3 requests   (or: brew install python && pip3 install ...)
  OR use the venv approach shown at the bottom.
"""

import argparse
import hashlib
import json
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime, timezone

def check_deps():
    missing = []
    try:
        import jwt
    except ImportError:
        missing.append("pyjwt")
    try:
        import boto3
    except ImportError:
        missing.append("boto3")
    try:
        import requests
    except ImportError:
        missing.append("requests")
    if missing:
        print(f"Missing dependencies: {', '.join(missing)}")
        print(f"Install with: pip3 install {' '.join(missing)}")
        sys.exit(1)

def make_jwt(key_path: str, key_id: str, issuer_id: str) -> str:
    import jwt
    key = Path(key_path).read_text()
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,  # 20 minutes
        "aud": "appstoreconnect-v1",
    }
    token = jwt.encode(payload, key, algorithm="ES256", headers={"kid": key_id})
    return token

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def submit(token: str, filename: str, sha256: str) -> dict:
    import requests
    resp = requests.post(
        "https://appstoreconnect.apple.com/notary/v2/submissions",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"submissionName": filename, "sha256": sha256},
    )
    resp.raise_for_status()
    return resp.json()

def upload_to_s3(attrs: dict, file_path: str):
    import boto3
    from botocore.config import Config
    s3 = boto3.client(
        "s3",
        aws_access_key_id=attrs["awsAccessKeyId"],
        aws_secret_access_key=attrs["awsSecretAccessKey"],
        aws_session_token=attrs["awsSessionToken"],
        region_name="us-east-1",
        config=Config(s3={"use_accelerate_endpoint": True}),
    )
    print(f"  Uploading to S3 bucket: {attrs['bucket']}")
    s3.upload_file(file_path, attrs["bucket"], attrs["object"])

def poll_status(token: str, submission_id: str, interval: int = 30) -> str:
    import requests
    url = f"https://appstoreconnect.apple.com/notary/v2/submissions/{submission_id}"
    attempt = 0
    while True:
        attempt += 1
        try:
            resp = requests.get(
                url,
                headers={"Authorization": f"Bearer {token}"},
                timeout=30,
            )
            resp.raise_for_status()
            data = resp.json()
            status = data["data"]["attributes"]["status"]
            print(f"  [{attempt}] {datetime.now(timezone.utc).strftime('%H:%M:%S')} Status: {status}")
            if status in ("Accepted", "Rejected", "Invalid"):
                return status
        except Exception as e:
            print(f"  [{attempt}] Network error: {e}, retrying...")
        time.sleep(interval)

def get_log(token: str, submission_id: str):
    import requests
    resp = requests.get(
        f"https://appstoreconnect.apple.com/notary/v2/submissions/{submission_id}/logs",
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    log_url = resp.json()["data"]["attributes"]["developerLogUrl"]
    log_resp = requests.get(log_url)
    return log_resp.json()

def staple(file_path: str):
    result = subprocess.run(["xcrun", "stapler", "staple", file_path], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Staple failed: {result.stderr}")
        sys.exit(1)
    result2 = subprocess.run(["xcrun", "stapler", "validate", file_path], capture_output=True, text=True)
    if result2.returncode != 0:
        print(f"Staple validation failed: {result2.stderr}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Notarize a DMG via Apple REST API")
    parser.add_argument("--key", required=True, help="Path to .p8 private key file")
    parser.add_argument("--key-id", required=True, help="Key ID (10-char alphanumeric from App Store Connect)")
    parser.add_argument("--issuer-id", required=True, help="Issuer ID (UUID from App Store Connect)")
    parser.add_argument("--file", required=True, help="Path to DMG to notarize")
    parser.add_argument("--poll-interval", type=int, default=30, help="Polling interval in seconds (default: 30)")
    args = parser.parse_args()

    check_deps()

    file_path = args.file
    filename = Path(file_path).name

    print(f"\n=== Apple Notarization REST API ===")
    print(f"File: {file_path}")

    print(f"\n[1/5] Generating JWT token...")
    token = make_jwt(args.key, args.key_id, args.issuer_id)
    print(f"  Token generated (expires in 20 min)")

    print(f"\n[2/5] Computing SHA-256...")
    sha256 = sha256_file(file_path)
    print(f"  {sha256}")

    print(f"\n[3/5] Starting submission...")
    result = submit(token, filename, sha256)
    attrs = result["data"]["attributes"]
    submission_id = result["data"]["id"]
    print(f"  Submission ID: {submission_id}")

    print(f"\n[4/5] Uploading to S3...")
    upload_to_s3(attrs, file_path)
    print(f"  Upload complete")

    print(f"\n[5/5] Polling for status (every {args.poll_interval}s)...")
    print(f"  Submission ID: {submission_id}")
    status = poll_status(token, submission_id, args.poll_interval)

    print(f"\n=== Final status: {status} ===")

    log = get_log(token, submission_id)
    if status == "Accepted":
        print("\nNotarization accepted!")
        issues = [i for i in log.get("issues", []) if i.get("severity") == "warning"]
        if issues:
            print(f"  Warnings ({len(issues)}):")
            for i in issues:
                print(f"    - {i.get('message')} [{i.get('path')}]")
        print(f"\nStapling ticket to {file_path}...")
        staple(file_path)
        print("Done! DMG is notarized and stapled.")
    else:
        print(f"\nNotarization {status}. Issues:")
        for issue in log.get("issues", []):
            print(f"  [{issue.get('severity')}] {issue.get('message')}")
            print(f"    Path: {issue.get('path')}")
        sys.exit(1)

if __name__ == "__main__":
    main()
