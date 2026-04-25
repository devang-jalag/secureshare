import json
import boto3
import os
import uuid
from datetime import datetime, timezone, timedelta

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        original_filename = body.get('filename', 'upload.bin')

        # Extract user identity from JWT via API Gateway authorizer context.
        # Prioritises 'sub' (Cognito Subject UUID) over email, which may not be
        # present depending on OAuth scope configuration.
        authorizer = event.get('requestContext', {}).get('authorizer', {})
        claims = authorizer.get('jwt', {}).get('claims') or authorizer.get('claims') or {}
        user_id = claims.get('sub') or claims.get('cognito:username') or claims.get('email') or 'anonymous'

        file_id = str(uuid.uuid4())
        s3_key = f"{file_id}/{original_filename}"

        now_dt = datetime.now(timezone.utc)
        uploaded_at = int(now_dt.timestamp())
        expiration_time = int((now_dt + timedelta(hours=24)).timestamp())

        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': s3_key,
                'ContentType': 'application/octet-stream'
            },
            ExpiresIn=3600
        )

        table.put_item(
            Item={
                'file_id': file_id,
                's3_key': s3_key,
                'original_filename': original_filename,
                'user_id': user_id,
                'uploaded_at': uploaded_at,
                'expires_at': expiration_time,
                'status': 'active'
            }
        )

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'file_id': file_id,
                'presigned_url': presigned_url,
                'expires_at': expiration_time
            })
        }

    except Exception as e:
        print(f"[ERROR] generate-url: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to generate upload URL.'})
        }
