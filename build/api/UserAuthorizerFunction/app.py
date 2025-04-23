def lambda_handler(event, context):
    print("=== AUTHORIZER START ===")
    print("Raw event:", event)

    token = event.get("authorizationToken")  # <-- THIS IS THE FIX
    print("Extracted token:", token)

    if token == "allow-token":
        print("Authorized ✔")
        return {
            "principalId": "test-user",
            "policyDocument": {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Action": "execute-api:Invoke",
                        "Effect": "Allow",
                        "Resource": event["methodArn"]
                    }
                ]
            }
        }

    print("Unauthorized ❌")
    raise Exception("Unauthorized")
