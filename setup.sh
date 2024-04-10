


#Platform:
CORTEX=cancelit-env-1.eba-pmamcuv5.us-east-1.elasticbeanstalk.com
CLOUDMRSTACK=cmr
_NN_=6334



# Create a bucket
BUCKET_NAME=mro-mainbucket-$_NN_
REGION=us-east-1
BACKSTACKNAME=MROBackstack-$_NN_
FRONTSTACKNAME=MROFrontstack


#_NN_ names


JobsBucketPName=xx--mroj-$_NN_
ResultsBucketPName=xx--mror-$_NN_
DataBucketPName=xx--mrod-$_NN_
FailedBucketPName=xx--mrof-$_NN_


aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION 

sam build -t Backend/template.yaml --use-container --build-dir build/back 
# sam package --template-file build/back/template.yaml --s3-bucket $BUCKET_NAME --output-template-file build/back/packaged-template.yaml
# sam deploy --template-file build/back/packaged-template.yaml --stack-name $BACKSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --region $REGION 

sam deploy --template-file build/back/template.yaml --stack-name $BACKSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides "CortexHost=$CORTEX JobsBucketPName=$JobsBucketPName ResultsBucketPName=$ResultsBucketPName DataBucketPName=$DataBucketPName FailedBucketPName=$FailedBucketPName"



#frontend

APITOKEN='mroptimum'
#cloud formaiton make an api-token




PROFILE_SERVER=$(aws cloudformation describe-stacks --stack-name $CLOUDMRSTACK --query "Stacks[0].Outputs[?OutputKey=='ProfileGetAPI'].OutputValue" --output text)
CLOUDMR_SERVER=$(aws cloudformation describe-stacks --stack-name $CLOUDMRSTACK --query "Stacks[0].Outputs[?OutputKey=='CmrApi'].OutputValue" --output text)
MRO_SERVER=$(aws cloudformation describe-stacks --stack-name $BACKSTACKNAME --query "Stacks[0].Outputs[?OutputKey=='MROApi'].OutputValue" --output text)


GITTOKENS=$CMRGITTOKEN

PARAMS="GithubToken=$GITTOKENS ApiToken=$APITOKEN CloudmrServer=$CLOUDMR_SERVER MroServer=$MRO_SERVER ProfileServer=$PROFILE_SERVER"


sam build -t Frontend/template.yaml --use-container --build-dir build/front
sam deploy --template-file build/front/template.yaml --stack-name $FRONTSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides sam deploy --template-file build/front/template.yaml --stack-name $FRONTSTACKNAME --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --resolve-image-repos --s3-bucket $BUCKET_NAME --parameter-overrides $(echo $PARAMS)



