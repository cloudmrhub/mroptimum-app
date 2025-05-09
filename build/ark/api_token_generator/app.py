import os
import json
import boto3
import secrets
import string

ssm = boto3.client('ssm')

def generate_api_token(length=32):
    """Generates a secure random alphanumeric token."""
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def lambda_handler(event, context):
    try:
        param_name = os.environ.get('PARAMETER_NAME', '/mro/api-token')
        token = generate_api_token()

        # Store the token in SSM Parameter Store (as a SecureString)
        ssm.put_parameter(
            Name=param_name,
            Value=token,
            Type='SecureString',
            Overwrite=True
        )

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'API token generated and stored.', 'token': token})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
