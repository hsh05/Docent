# Docent

[![CI/CD Pipeline](https://img.shields.io/badge/build-passing-brightgreen?logo=github-actions)](https://github.com/)
[![Flutter](https://img.shields.io/badge/Flutter-Stable-02569B?logo=flutter)](https://flutter.dev/)
[![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi)](https://fastapi.tiangolo.com/)

Docent is an AI-powered educational platform designed to gamify the Feynman Learning Technique. By challenging users to explain complex topics out loud, Docent evaluates conceptual accuracy in real-time, identifies knowledge gaps, and dynamically generates spaced-repetition reviews.

## Core Features

* **Real-Time Voice Sessions:** Utilizes WebSocket architecture to stream audio bytes directly to the backend, enabling instantaneous, low-latency AI conversational responses without standard HTTP polling delays.
* **The Feynman Engine:** Evaluates user spoken responses for conceptual accuracy, rather than just keyword matching, generating dynamic follow-up questions and audio dialogue.
* **ML-Driven Diagnostic Clustering:** Converts failed concepts into vector embeddings using `text-embedding-3-small` and applies K-Means clustering via `scikit-learn` to diagnose underlying semantic weaknesses across multiple study sessions.
* **Automated CI/CD:** Fully automated GitHub Actions deployment pipeline that compiles, zips, and publishes native Android (`.apk`) and Windows (`.exe`) binaries upon every version tag push.

## Architecture & Tech Stack

### Frontend (Client)
* **Framework:** Flutter (Android & Windows)
* **State Management:** Riverpod 2.0+ (Notifier Architecture)
* **Real-time Networking:** `web_socket_channel` with aggressive Exponential Backoff reconnection strategies for resilient mobile network handling.
* **Audio Processing:** Native microphone streaming and chunked byte playback.

### Backend (Server)
* **Framework:** FastAPI (Python)
* **Database:** PostgreSQL managed via SQLAlchemy ORM.
* **AI Integration:** OpenAI API (Whisper-1 for STT, GPT-4o for logical evaluation, TTS-1 for voice generation, and Realtime API for live streaming).
* **Machine Learning:** `numpy` and `scikit-learn` for K-Means unsupervised clustering on user error data.

## Analytics Dashboard

Docent includes a persistent native dashboard that visualizes aggregate user performance. Rather than forcing users to review raw session transcripts, the backend calculates moving averages and surfaces AI-generated coaching insights based on clustered failure data.

## Local Development Setup

### Prerequisites
* Flutter SDK (Stable Channel)
* Python 3.10+
* PostgreSQL

### Backend Setup
1. Navigate to the backend directory.
2. Create a virtual environment: `python -m venv venv`
3. Activate the environment and install dependencies: `pip install -r requirements.txt`
4. Set up your `.env` file with your `DATABASE_URL`, `OPENAI_API_KEY`, and `SECRET_KEY`.
5. Run the server: `uvicorn main:app --reload`

### Frontend Setup
1. Navigate to the root directory.
2. Install dependencies: `flutter pub get`
3. Generate required native platform code: `flutter run`

## Releases

Pre-compiled, production-ready binaries for Windows and Android are automatically generated via GitHub Actions. Navigate to the **Releases** tab to download the latest `.exe` or `.apk`.