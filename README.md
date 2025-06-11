
 aws configure --profile nyu
 e_aws_ecr_profile_login nyu


1. create update ECR
```bash
cd backend/caculation/src
bash setup.sh
```



   sam build --use-container --profile nyu
   sam deploy \
     --stack-name mroptimum-app-test \
     --profile nyu \
     --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
     --resolve-image-repos \
     --resolve-s3


# new version of MR optimum backend made as nested backend
1. ark


[*Dr. Eros Montin, PhD*]\
(http://me.biodimensional.com)\
**46&2 just ahead of me!**








