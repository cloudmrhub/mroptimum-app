docker build  -t mroptimum-run-job-lambda:latest -f DockerfileLambda .
docker tag mroptimum-run-job-lambda:latest   469266894233.dkr.ecr.us-east-1.amazonaws.com/mroptimum-run-job-lambda:latest
docker push 469266894233.dkr.ecr.us-east-1.amazonaws.com/mroptimum-run-job-lambda:latest
#docker run --rm -it   --entrypoint /bin/bash   469266894233.dkr.ecr.us-east-1.amazonaws.com/mroptimum-run-job-lambda:latest

