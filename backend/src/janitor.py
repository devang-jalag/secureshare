import boto3
import os
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Attr

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(TABLE_NAME)

def run_janitor():
    print(f"[INFO] Janitor starting. Bucket: {BUCKET_NAME}, Table: {TABLE_NAME}")

    now = int(datetime.now(timezone.utc).timestamp())

    try:
        # DynamoDB TTL handles row-level expiry automatically. This scan targets
        # S3 object deletion for items whose TTL has lapsed but whose S3 objects
        # remain, ensuring no orphaned storage accumulates between TTL sweep cycles.
        response = table.scan(
            FilterExpression=Attr('expires_at').lte(now)
        )

        expired_items = response.get('Items', [])
        print(f"[INFO] {len(expired_items)} expired item(s) found.")

        for item in expired_items:
            s3_key = item['s3_key']
            file_id = item['file_id']

            try:
                s3_client.delete_object(Bucket=BUCKET_NAME, Key=s3_key)
                table.delete_item(Key={'file_id': file_id})
                print(f"[INFO] Deleted: {file_id}")
            except Exception as e:
                print(f"[ERROR] Failed to delete {file_id}: {str(e)}")

    except Exception as e:
        print(f"[ERROR] Table scan failed: {str(e)}")

    print("[INFO] Janitor complete.")

if __name__ == "__main__":
    run_janitor()
