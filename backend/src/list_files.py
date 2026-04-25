import json
import boto3
import os
import decimal
from datetime import datetime, timezone

# Workaround: boto3 deserializes DynamoDB numeric types as decimal.Decimal,
# which is not JSON-serializable by default.
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return int(obj)
        return super(DecimalEncoder, self).default(obj)

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        authorizer = event.get('requestContext', {}).get('authorizer', {})
        claims = authorizer.get('jwt', {}).get('claims') or authorizer.get('claims') or {}
        user_id = claims.get('sub') or claims.get('cognito:username') or claims.get('email')

        if not user_id:
            return {'statusCode': 401, 'body': json.dumps({'error': 'Unauthorized'})}

        now = int(datetime.now(timezone.utc).timestamp())

        response = table.scan()
        items = response.get('Items', [])

        active_files = [
            item for item in items
            if item.get('user_id') == user_id and item.get('expires_at', 0) > now
        ]

        active_files.sort(key=lambda x: x.get('uploaded_at', 0), reverse=True)

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'files': active_files}, cls=DecimalEncoder)
        }

    except Exception as e:
        print(f"[ERROR] list-files: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': 'Failed to retrieve file list.'})}
