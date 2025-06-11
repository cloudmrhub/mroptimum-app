
# add username and password of your dockerhub
aws secretsmanager create-secret \
    --name dockerhub-credentials \
    --secret-string '{"username":"----","password":"---"}' \
    --region $REGION