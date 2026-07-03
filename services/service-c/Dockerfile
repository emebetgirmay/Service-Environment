FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY logger.py .

RUN groupadd -r appgroup && useradd -r -g appgroup appuser
USER appuser

EXPOSE 3003

CMD ["python", "app.py"]
