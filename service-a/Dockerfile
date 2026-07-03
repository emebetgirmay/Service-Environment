FROM python:3.12.3-slim

# Install curl for service discovery and health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements from workspace root
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy service source code
COPY service-a/ /app/service-a/
COPY shared/ /app/shared/

# Create non-root user for security
RUN addgroup --system --gid 1001 appgroup && \
    adduser --system --uid 1001 --ingroup appgroup appuser && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 3001

ENV PYTHONUNBUFFERED=1

CMD ["python", "service-a/app.py"]
