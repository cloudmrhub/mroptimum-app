################################################################################
# Stage 1: Install all dependencies into /app (build stage)
################################################################################
FROM python:3.10-slim AS build

WORKDIR /app
RUN apt-get update \
  && apt-get install -y --no-install-recommends git \
  && rm -rf /var/lib/apt/lists/*
# Copy requirements and install
COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

RUN pip install git+https://github.com/cloudmrhub/mroptimum-tools.git
COPY app.py .

################################################################################
# Stage 2: Lambda image (uses AWS Lambda Python base with RIC)
################################################################################
FROM public.ecr.aws/lambda/python:3.10 AS lambda-image

# Copy /app (code + installed libs) from the build stage to /var/task
COPY --from=build /app /var/task
ENV SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt

# Tell Lambda to use handler.lambda_handler
CMD ["handler.lambda_handler"]

################################################################################
# Stage 3: Fargate image (plain Python, entrypoint is “python app.py”)
################################################################################
FROM python:3.10-slim AS fargate-image

WORKDIR /app
ENV SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt

# Copy everything (code + installed libs) from the build stage
COPY --from=build /app /app

# When ECS runs this container, it will execute “python app.py”
ENTRYPOINT ["python", "app.py"]
