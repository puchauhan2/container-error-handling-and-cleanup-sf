import json
import boto3
import time
import os
import subprocess
from botocore.exceptions import ClientError

# Static values
repo_url = os.getenv('GITHUB_REPO_URL')
github_api_base_url = os.getenv('GITHUB_API_BASE_URL')

secrets_client = boto3.client('secretsmanager')
dynamodb_client = boto3.client('dynamodb')

def update_dynamodb_on_failure(dynamodb_record):
    update_expression = "SET #execution_status = :execution_status, #execution_on = :execution_on, #execution_comment = :execution_comment, #status = :status"
    expression_attribute_names = {
        "#execution_status": "execution_status",
        "#execution_on": "execution_on",
        "#execution_comment": "execution_comment",
        "#status": "status"
    }
    expression_attribute_values = {
        ":execution_status": {"S": 'Failed'},
        ":execution_on": {"S": str(int(time.time()))},
        ":execution_comment": {"S": 'Execution failed due to some error. Please contact Cloud Engineers to retry this.'},
        ":status": {"S": 'Failure'}
    }
    
    # Update the DynamoDB table
    response = dynamodb_client.update_item(
        TableName='new_account_request_tbl',
        Key={
            'request_id': {'S': dynamodb_record['NewImage']['request_id']['S']},
            'requested_by': {'S': dynamodb_record['NewImage']['requested_by']['S']}
        },
        UpdateExpression=update_expression,
        ExpressionAttributeNames=expression_attribute_names,
        ExpressionAttributeValues=expression_attribute_values,
        ReturnValues='ALL_NEW'
    )
    
# Fetch the PAT from AWS Secrets Manager
def get_github_token(secret_name):
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret = response['SecretString']
        return secret
    except Exception as e:
        raise Exception(f"Failed to retrieve GitHub token: {e}")

def lambda_handler(event, context):
    try:
        # Extract necessary details from the event
        error_info = event.get('errorInfo', {})
        dynamodb_record = event.get('processDynamoDBRecordResult', {}).get('dynamodbRecord')
        pipeline_status = event.get('checkFinalPipelineStatusResult', {}).get('pipelineStatus')
        branch_name = event.get('gitHubLZAConfigFileUpdateResult', {}).get('branchName')
        print('branch_name: ', branch_name, 'pipeline_status: ', pipeline_status)
        
        if pipeline_status == 'Succeeded':
            update_dynamodb_on_failure(dynamodb_record)
            return {
                "status": "Requested aws account is created, skipping cleanup."
            }
        elif not branch_name:
            update_dynamodb_on_failure(dynamodb_record)
            return {
                "status": "No branch name found, skipping cleanup."
            }
            
        github_token = get_github_token(os.getenv('GITHUB_TOKEN_SECRET_NAME'))
        
        # Start CodeBuild job
        command = f"./script.sh '{repo_url}' '{github_token}' '{branch_name}' '{github_api_base_url}'"
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        if process.returncode != 0:
            print(f"Error executing script: {stderr.decode('utf-8')}")
            raise Exception('Error occured while merging the account details to main branch on GitHub.')
        update_dynamodb_on_failure(dynamodb_record) 
        return {
            "status": "cleanup_completed"
        }
    except KeyError as e:
        print(f"KeyError occurred: {str(e)}")
        raise e
    except ClientError as e:
        print(f"ClientError occurred: {e.response['Error']['Message']}")
        raise e
    except ValueError as e:
        print(f"ValueError occurred: {str(e)}")
        raise e
    except Exception as e:
        raise e
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }
