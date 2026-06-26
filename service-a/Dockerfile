FROM python:3.12-slim

# Install curl for service discovery verification
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements from workspace root
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy service source code
COPY service-a/ /app/service-a/

EXPOSE 3001

ENV PYTHONUNBUFFERED=1

CMD ["python", "service-a/app.py"]
