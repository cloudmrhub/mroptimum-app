FROM public.ecr.aws/lambda/python:3.10

# Install required system packages
RUN yum install -y git gcc gcc-c++ make cmake

# Set working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# Install mroptimum-tools and its C-extension dependencies
RUN pip install --no-cache-dir git+https://github.com/cloudmrhub/mroptimum-tools.git

# Copy function code and local module
COPY app.py .
COPY pynico_eros_montin ./pynico_eros_montin

# Ensure Python can find the local module
# ENV PYTHONPATH="${PYTHONPATH}:/var/task/pynico_eros_montin"

# Set Lambda handler
CMD [ "app.handler" ]
