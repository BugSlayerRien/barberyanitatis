FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgles2 \
    libegl1 \
    libgl1 \
    libgl1-mesa-dri \
    libglib2.0-0 \
    libgomp1 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

ENV PYTHONUNBUFFERED=1
ENV MEDIAPIPE_DISABLE_GPU=1
ENV LIBGL_ALWAYS_SOFTWARE=1

EXPOSE 8000
CMD uvicorn api:app --host 0.0.0.0 --port ${PORT:-8000}
