from pathlib import Path

import boto3


def upload(bucket: str, key: str, source: Path) -> str:
    client = boto3.client("s3")
    response = client.put_object(Bucket=bucket, Key=key, Body=source.read_bytes())
    return response["ETag"]

