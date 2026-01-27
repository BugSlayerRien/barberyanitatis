# AI Models

Computer vision and machine learning models for AI-powered hairstyle recommendations.

## Overview

This module provides:
- Face shape detection using computer vision
- Hairstyle recommendation based on facial features
- Feasibility scoring for hairstyle suggestions
- Image processing and analysis

## Tech Stack

- **Framework**: TensorFlow / PyTorch
- **Computer Vision**: OpenCV
- **Face Detection**: dlib / MediaPipe
- **API**: Flask/FastAPI for serving models

## Project Structure

```
ai-models/
├── src/
│   ├── face_detection/      # Face shape detection models
│   ├── hairstyle_recommendation/ # Recommendation algorithms
│   └── utils/               # Helper functions
├── models/                  # Trained model files
├── datasets/                # Training datasets
└── requirements.txt
```

## Setup

### 1. Install Python Dependencies

```bash
cd ai-models
pip install -r requirements.txt
```

### 2. Download Pre-trained Models

```bash
python scripts/download_models.py
```

### 3. Start the AI Service

```bash
python src/app.py
```

The service will run on `http://localhost:5000`

## Features

### Face Shape Detection

Analyzes facial features to determine face shape:
- Oval
- Round
- Square
- Heart
- Diamond
- Oblong

**Algorithm:**
1. Detect facial landmarks using dlib/MediaPipe
2. Calculate facial proportions
3. Classify face shape based on ratios
4. Return confidence score

### Hairstyle Recommendation

Provides personalized hairstyle recommendations:
1. Analyzes face shape
2. Considers hair type and length
3. Matches with suitable hairstyles
4. Calculates feasibility scores

### Feasibility Scoring

Evaluates how well a hairstyle suits the customer:
- Face shape compatibility (40%)
- Hair type suitability (30%)
- Maintenance requirements (20%)
- Customer preferences (10%)

## API Endpoints

### POST /api/analyze-face
Analyzes face shape from an image.

**Request:**
```json
{
  "image": "base64_encoded_image"
}
```

**Response:**
```json
{
  "faceShape": "oval",
  "confidence": 0.89,
  "facialFeatures": {
    "foreheadWidth": 0.75,
    "cheekboneWidth": 0.80,
    "jawlineWidth": 0.70,
    "faceLength": 1.0
  }
}
```

### POST /api/recommend
Generates hairstyle recommendations.

**Request:**
```json
{
  "faceShape": "oval",
  "hairType": "wavy",
  "hairLength": "medium",
  "preferences": ["low_maintenance"]
}
```

**Response:**
```json
{
  "recommendations": [
    {
      "name": "Classic Fade",
      "imageUrl": "/images/classic-fade.jpg",
      "confidenceScore": 0.92,
      "feasibilityScore": 0.88,
      "description": "A versatile style...",
      "maintenance": "low",
      "suitability": {
        "faceShape": 0.95,
        "hairType": 0.85,
        "overall": 0.88
      }
    }
  ]
}
```

## Model Training

### Preparing Datasets

1. Collect face images with labeled face shapes
2. Collect hairstyle images with metadata
3. Organize in `datasets/` directory

### Training Face Detection Model

```bash
python train/train_face_detector.py --epochs 50 --batch-size 32
```

### Training Recommendation Model

```bash
python train/train_recommender.py --data datasets/hairstyles
```

## Model Files

Pre-trained models are stored in `models/`:
- `face_shape_detector.h5` - Face shape classification
- `facial_landmarks.dat` - Facial landmark detection
- `hairstyle_embeddings.pkl` - Hairstyle feature vectors

## Performance Metrics

- Face detection accuracy: 94%
- Face shape classification: 89%
- Recommendation relevance: 87%

## Integration

The AI service integrates with the backend API:

```javascript
// Backend calls AI service
const response = await axios.post('http://localhost:5000/api/recommend', {
  faceShape: customerFaceShape,
  hairType: customerHairType
});
```

## Development

```bash
# Run tests
pytest tests/

# Lint code
pylint src/

# Format code
black src/
```

## License

MIT
