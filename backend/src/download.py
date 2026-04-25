import json
import boto3
import os
from datetime import datetime, timezone

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        file_id = body.get('file_id')

        if not file_id:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Missing required parameter: file_id'})
            }

        response = table.get_item(Key={'file_id': file_id})
        item = response.get('Item')

        if not item:
            return {
                'statusCode': 404,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'File not found or has already been deleted.'})
            }

        now = int(datetime.now(timezone.utc).timestamp())
        if item.get('expires_at', 0) < now:
            return {
                'statusCode': 410,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'File has expired and is no longer available.'})
            }

        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': item['s3_key'],
                'ResponseContentDisposition': f"attachment; filename=\"{item['original_filename']}\""
            },
            ExpiresIn=3600
        )

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'download_url': presigned_url,
                'original_filename': item['original_filename']
            })
        }

    except Exception as e:
        print(f"[ERROR] download-url: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Failed to generate download URL.'})
        }
