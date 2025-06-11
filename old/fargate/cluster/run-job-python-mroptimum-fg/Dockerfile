FROM python:3.10-slim

# Copy requirements and install dependencies
COPY requirements.txt /app/requirements.txt
WORKDIR /app
RUN pip install -r requirements.txt
RUN apt-get update && apt-get install -y git
RUN pip install git+https://github.com/cloudmrhub/mroptimum-tools.git

# Copy your application code
COPY main.py /app/main.py

# Set environment variable for SSL certificates (if needed)
ENV SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt

# Use your main script as the container entrypoint
CMD ["python", "main.py"]
