sam logs -n RunJobFunction --stack-name testbackendmro --tail




aws s3 cp run-job-python-FG.zip s3://source-docker-mroptimum/run-job-python-FG.zip

aws logs tail /ecs/mroptimum-processor --follow

# to build 

you ned to uplaod the docker zip file in a s3 bycket in this case 

source-docker-mroptimum
run-job-python-FG.zip





deploymant
```bash

sam build --use-container

subnets_raw=$(aws ec2 describe-subnets --query "Subnets[].SubnetId" --output text)

# Convert the output into a comma-separated list.
subnets=$(echo $subnets_raw | tr ' ' ',')

# Deploy your SAM stack, supplying your SourceBucket, SourceKey, and VpcSubnets parameters
sam deploy \
  --stack-name testbackendmro \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
      SourceBucket=source-docker-mroptimum \
      SourceKey=run-job-python-FG.zip \
      VpcSubnets="$subnets" \
      --guided

```


aws logs tail /ecs/mroptimum-processor --follow --region us-east-1


 aws ecs describe-tasks --cluster testbackendmro-MyEcsCluster-isUihtvXafSu --tasks 666e264a1c6b41f8974a5bf8627f1cc7 >/g/a.txt



  aws ecs list-tasks --cluster testbackendmro-MyEcsCluster-isUihtvXafSu --desired-status STOPPED




AWS Fargate only supports certain combinations of CPU and memory:

CPU (vCPU)	Memory (MiB)
256 (0.25)	512, 1024, 2048
512 (0.5)	1024, 2048, 3072, 4096
1024 (1)	2048, 3072, 4096, 5120, 6144, 7168, 8192
2048 (2)	4096, 5120, 6144, 7168, 8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384
4096 (4)	8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384, 17408, 18432, 19456, 20480, 21504, 22528, 23552, 24576, 25600, 26624, 27648, 28672, 29696, 30720
8192 (8)	16384 - 61440 (16GB - 60GB)
16384 (16)	32768 - 120000 (32GB - 120GB)