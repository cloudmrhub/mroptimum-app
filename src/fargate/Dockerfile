FROM python:3.10-slim

# Install build dependencies and git for mroptimum-tools installation
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install -r requirements.txt

# Install mroptimum-tools from GitHub
RUN pip install git+https://github.com/cloudmrhub/mroptimum-tools.git

# Copy your application code
COPY app.py /app/app.py  

# Set environment variable for SSL certificates (if needed)
# ENV SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt

# Use your main script as the container entrypoint
CMD ["python", "app.py"]
