


#random part in the stack name
_NN_=friday63112april24

# to be filled by cmr

CORTEX=cancelit-env-1.eba-pmamcuv5.us-east-1.elasticbeanstalk.com
CLOUDMRSTACK=cmr

PROFILE=https://ewjjq013u0.execute-api.us-east-1.amazonaws.com/profile
CLOUDMRCMR=https://ewjjq013u0.execute-api.us-east-1.amazonaws.com/

GITTOKENS=$CMRGITTOKEN


# Create a bucket
BUCKET_NAME=mro-mainbucket-$_NN_
REGION=us-east-1
COMMONSTACKNAME=MROCommon-$_NN_
BACKSTACKNAME=MROBackstack-$_NN_
FRONTSTACKNAME=MROFrontstack-$_NN_
USAGEPLANSTACKNAME=USAGEPLAN-$_NN_




JobsBucketPName=xx--mroj-$_NN_
ResultsBucketPName=xx--mror-$_NN_
DataBucketPName=xx--mrod-$_NN_
FailedBucketPName=xx--mrof-$_NN_


#check if $BUCKET_NAME exists
aws s3api head-bucket --bucket $BUCKET_NAME --region $REGION
if [ $? -eq 0 ]; then
    echo "Bucket exists"
else
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION 
fi



#Build common resources

sam build -t Common/template.yaml --use-container --build-dir build/common
echo "Building common resources"
sam deploy --template-file build/common/template.yaml --stack-name $COMMONSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --region $REGION --resolve-image-repos --s3-bucket $BUCKET_NAME
echo "Deploying common resources"
#wait for the stack to be created
echo "Waiting for stack to be created"
aws cloudformation wait stack-create-complete --stack-name $COMMONSTACKNAME

REQUESTS_LAYER=$(aws cloudformation describe-stacks --stack-name $COMMONSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='RequestsARN'].OutputValue" --output text)

echo "Requests layer is $REQUESTS_LAYER"
echo "Common resources deployed"

echo "Building backend resources"
sam build -t Backend/template.yaml --use-container --build-dir build/back 
# sam package --template-file build/back/template.yaml --s3-bucket $BUCKET_NAME --output-template-file build/back/packaged-template.yaml
# sam deploy --template-file build/back/packaged-template.yaml --stack-name $BACKSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --region $REGION 

sam deploy --template-file build/back/template.yaml --stack-name $BACKSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides "CortexHost=$CORTEX JobsBucketPName=$JobsBucketPName ResultsBucketPName=$ResultsBucketPName DataBucketPName=$DataBucketPName FailedBucketPName=$FailedBucketPName RequestsLayerARN=$REQUESTS_LAYER"  


echo "Waiting for stack to be created"
aws cloudformation wait stack-create-complete --stack-name $BACKSTACKNAME



API_ID=$(aws cloudformation describe-stacks --stack-name $BACKSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='ApiId'].OutputValue" --output text)
STAGE_NAME=$(aws cloudformation describe-stacks --stack-name $BACKSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='StageName'].OutputValue" --output text) 


sam build -t UsagePlan/template.yaml --use-container --build-dir build/usageplan
sam deploy --template-file build/usageplan/template.yaml --stack-name $USAGEPLANSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides "ApiGatewayApi=$API_ID StageName=$STAGE_NAME"





# get the value of the api-token from the cloudformation stack
#APITOKEN=$(aws cloudformation describe-stacks --stack-name $CLOUDMRSTACK --query "Stacks[0].Outputs[?OutputKey=='ApiToken'].OutputValue" --output text)    

TOKEN_KEY=$(aws cloudformation describe-stacks --stack-name $USAGEPLANSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='ApiKey'].OutputValue" --output text)

APITOKEN=$(aws apigateway get-api-key --api-key $TOKEN_KEY --include-value | jq -r '.value')

#cloud formaiton make an api-token



#frontend
PROFILE_SERVER=$(aws cloudformation describe-stacks --stack-name $CLOUDMRSTACK --query "Stacks[0].Outputs[?OutputKey=='ProfileGetAPI'].OutputValue" --output text)
if [ $? -eq 0 ]; then
    echo "Profile server exists"
else
    PROFILE_SERVER=$PROFILE
fi



CLOUDMR_SERVER=$(aws cloudformation describe-stacks --stack-name $CLOUDMRSTACK --query "Stacks[0].Outputs[?OutputKey=='CmrApi'].OutputValue" --output text)
if [ $? -eq 0 ]; then
    echo "cluodmr server exists"
else
    CLOUDMR_SERVER=$CLOUDMRCMR
fi


MRO_SERVER=$(aws cloudformation describe-stacks --stack-name $BACKSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='MROApi'].OutputValue" --output text)


# GITTOKENS=$CMRGITTOKEN


PARAMS="GithubToken=$GITTOKENS ApiToken=$APITOKEN CloudmrServer=$CLOUDMR_SERVER MroServer=$MRO_SERVER ProfileServer=$PROFILE_SERVER ApiUrl=aa"


sam build -t Frontend/template.yaml --use-container --build-dir build/front
sam deploy --template-file build/front/template.yaml --stack-name $FRONTSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides $PARAMS
# sam deploy --template-file build/front/template.yaml --stack-name $FRONTSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides $(echo $PARAMS)


FRONTEND_URL=$(aws cloudformation describe-stacks --stack-name $FRONTSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='AmplifyAppDomain'].OutputValue" --output text)

echo "Frontend URL is $FRONTEND_URL"
