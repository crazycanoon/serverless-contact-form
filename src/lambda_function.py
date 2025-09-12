import json
import os
import boto3
from datetime import datetime
import uuid

# Get the DynamoDB table name from an environment variable
TABLE_NAME = os.environ.get('TABLE_NAME', 'ContactFormSubmissions')
# Create a DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    """
    Handles form submissions from API Gateway.
    """
    print(f"Received event: {event}")

    try:
        # API Gateway wraps the request body in a string, so we need to parse it.
        body = json.loads(event.get('body', '{}'))

        # Basic validation: Check if required fields are present
        required_fields = ['name', 'email', 'message']
        if not all(field in body for field in required_fields):
            print("Validation Failed: Missing required fields")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*' # Required for CORS
                },
                'body': json.dumps({'error': 'Missing required fields: name, email, message'})
            }

        # Extract data from the request body
        name = body['name']
        email = body['email']
        message = body['message']
        
        # Create a unique ID and a timestamp for the submission
        submission_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()

        # Create the item to be stored in DynamoDB
        item = {
            'id': submission_id,
            'name': name,
            'email': email,
            'message': message,
            'submittedAt': timestamp
        }
        
        # Put the item into the DynamoDB table
        table.put_item(Item=item)
        print(f"Successfully saved item: {item}")
        
        # Return a success response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*' # Required for CORS
            },
            'body': json.dumps({'message': 'Form submitted successfully!'})
        }

    except Exception as e:
        print(f"Error processing request: {str(e)}")
        # Return an error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'An internal error occurred.'})
        }
