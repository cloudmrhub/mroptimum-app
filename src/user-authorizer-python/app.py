import os
import json
import urllib3

http = urllib3.PoolManager()

def lambda_handler(event, context):
    try:
        token = event.get("headers", {}).get("authorization", "")

        if not token:
            raise ValueError("Missing token")

        # External auth call (e.g. to CloudMR)
        resp = http.request(
            "GET",
            f"{os.environ['Host']}/api/auth/profile",
            headers={
                "Authorization": token,
                "User-Agent": "cloudmr client",
                "From": "mr-optimum@cloudmrhub.org"
            }
        )

        data = json.loads(resp.data.decode("utf-8"))

        if resp.status != 200 or "id" not in data or "name" not in data:
            raise ValueError("Unauthorized")

        return {
            "isAuthorized": True,
            "context": {
                "user_id": data["id"],
                "user_name": data["name"],
                "user_email": data.get("email", "")
            }
        }

    except Exception as e:
        return {
            "isAuthorized": False,
            "context": {
                "error": str(e)
            }
        }
