import os
import json
import base64
import websockets
import asyncio
import numpy as np
from sklearn.cluster import KMeans
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status, WebSocket, WebSocketDisconnect
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from dotenv import load_dotenv
from openai import OpenAI

import models
from database import engine, get_db
from auth import get_password_hash, verify_password, create_access_token, get_current_user, ACCESS_TOKEN_EXPIRE_MINUTES
from datetime import datetime, timedelta

models.Base.metadata.create_all(bind=engine)

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

app = FastAPI(title="Docent API")

OPENAI_REALTIME_URL = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"

@app.post("/api/auth/register", status_code=status.HTTP_201_CREATED)
def register_user(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    if len(form_data.password) > 72:
        raise HTTPException(status_code=400, detail="Password must be 72 characters or less")
    
    # Check if user exists
    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if user:
        raise HTTPException(status_code=400, detail="Username already registered")
    
    # Create new user
    hashed_password = get_password_hash(form_data.password)
    new_user = models.User(username=form_data.username, hashed_password=hashed_password)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"message": "User created successfully"}

@app.post("/api/auth/login")
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, # FIXED: statu_code -> status_code
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
        
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer", "user_id": user.id}

@app.post("/api/sessions/start")
async def start_session(
    audio_file: UploadFile = File(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Save uploaded audio to temp file
    temp_file_path = f"temp_{audio_file.filename}"
    with open(temp_file_path, "wb") as buffer:
        buffer.write(await audio_file.read())
        
    try:
        # Transcribe
        with open(temp_file_path, "rb") as audio:
            transcript_response = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio
            )
        transcript = transcript_response.text
        
        # Generate questions
        system_prompt = """You are a student preparing for an exam. 
        The user has just provided a long summary of the study material. 
        Analyze the content size and generate a list of questions to ask the user. 
        Generate between 10 and 20 questions, ensuring at least 2 questions per distinct topic mentioned. 
        Return strictly in JSON format: {"questions": ["Q1", "Q2"]}"""
        
        completion = client.chat.completions.create(
            model="gpt-4o",
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": transcript}
            ]
        )
        
        response_data = json.loads(completion.choices[0].message.content)
        questions_list = response_data.get("questions", [])
        
        new_session = models.StudySession(
            user_id=current_user.id,
            topic_summary=transcript
        )
        db.add(new_session)
        db.commit()
        db.refresh(new_session)
        
        # Return the payload to Flutter
        return {
            "session_id": new_session.id,
            "transcript_summary": transcript,
            "questions": questions_list
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
@app.post("/api/sessions/evaluate")
async def evaluate_answer(
    session_id: int = Form(...),
    current_question: str = Form(...),
    audio_file: UploadFile = File(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # FIXED: Removed the trailing comma at the end of this line
    session = db.query(models.StudySession).filter(models.StudySession.id == session_id).first() 
    if not session or session.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to access this session")
    
    temp_audio_path = f"temp_answer_{audio_file.filename}"
    temp_tts_path = f"temp_tts_{session_id}.mp3"
    
    with open(temp_audio_path, "wb") as buffer:
        buffer.write(await audio_file.read())
        
    try:
        # Transcribe the answer
        with open(temp_audio_path, "rb") as audio:
            transcript_response = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio
            )
        user_transcript = transcript_response.text
        
        system_prompt = f"""You are a student. The user is your teacher. 
        You previously asked them: "{current_question}". 
        Evaluate their answer. First, evaluate if it is conceptually accurate. 
        Then, formulate a short, 1-2 sentence dialogue response. 
        If wrong, act confused. If right, act as if you understand it now. 
        Return strictly in JSON: {{"is_accurate": true, "dialogue": "Wow, that makes sense!"}}"""
        
        completion = client.chat.completions.create(
            model="gpt-4o",
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_transcript}
            ]
        )
        
        evaluation = json.loads(completion.choices[0].message.content)
        is_accurate = evaluation.get("is_accurate", False) # FIXED: Lowercase 'a'
        dialogue = evaluation.get("dialogue", "I'm a bit lost.")
        
        # Save to DB
        question_result = models.QuestionResult(
            session_id=session_id,
            question_text=current_question,
            passed=is_accurate
        )
        db.add(question_result)
        db.commit()
        
        # Generate audio
        tts_response = client.audio.speech.create(
            model="tts-1",
            voice="nova",
            input=dialogue # FIXED: Removed quotes so it passes the variable
        )
        tts_response.stream_to_file(temp_tts_path)
        
        # Encode audio
        with open(temp_tts_path, "rb") as tts_file:
            audio_base64 = base64.b64encode(tts_file.read()).decode('utf-8') # FIXED: Changed colon to equals sign
            
        return {
            "is_accurate": is_accurate,
            "dialogue": dialogue,
            "audio_base64": audio_base64
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_audio_path):
            os.remove(temp_audio_path)
        if os.path.exists(temp_tts_path):
            os.remove(temp_tts_path)

@app.get("/api/users/history")
async def get_user_history(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        # Fetch all sessions
        sessions = db.query(models.StudySession).filter(
            models.StudySession.user_id == current_user.id
        ).order_by(models.StudySession.created_at.desc()).all()
        
        history_data = []
        for session in sessions:
            # Calculate score dynamically
            total_questions = len(session.questions)
            passed_questions = sum(1 for q in session.questions if q.passed)
            score = (passed_questions / total_questions * 100) if total_questions > 0 else 0
            
            # Create short preview
            summary_preview = session.topic_summary[:80] + "..." if len(session.topic_summary) > 80 else session.topic_summary
            
            history_data.append({
                "session_id": session.id,
                "date": session.created_at.strftime("%b %d, %Y"),
                "topic_preview": summary_preview,
                "score": score,
                "passed": passed_questions,
                "total": total_questions
            })
            
        return {"history": history_data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/api/sessions/daily-review")
async def generate_daily_review(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        failed_questions = db.query(models.QuestionResult).join(
            models.StudySession, models.QuestionResult.session_id == models.StudySession.id
        ).filter(
            models.StudySession.user_id == current_user.id,
            models.QuestionResult.passed == False
        ).order_by(models.QuestionResult.id.desc()).limit(5).all()
        
        if not failed_questions:
            return {
                "message": "You are all caught up! No failed concepts to review today.",
                "session_id": None,
                "questions": []
            }
            
        failed_concepts = [q.question_text for q in failed_questions]
        concepts_string = "\n".join(failed_concepts)
        
        system_prompt = f"""You are an expert tutor building a daily review quiz.
        The student previously failed to answer these specific questions correctly:
        {concepts_string}
        
        Rephrase these concepts into brand new, distinct questions to test if they actually understand the underlying material now.
        Return exactly {len(failed_concepts)} questions.
        Return strictly in JSON format: {{"questions": ["New Q1", "New Q2"]}}"""
        
        completion = client.chat.completions.create(
            model="gpt-4o",
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt}
            ]
        )
        
        response_data = json.loads(completion.choices[0].message.content)
        new_questions_list = response_data.get("questions", [])
        
        new_session = models.StudySession(
            user_id=current_user.id,
            topic_summary=f"Daily Spaced Repetition Review ({datetime.now().strftime('%b %d')})"
        )
        db.add(new_session)
        db.commit()
        db.refresh(new_session)
        
        return {
            "session_id": new_session.id,
            "transcript_summary": new_session.topic_summary,
            "questions": new_questions_list
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/api/users/weakness-insight")
async def get_weakness_insight(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        failed_questions = db.query(models.QuestionResult).join(
            models.StudySession, models.QuestionResult.session_id == models.StudySession.id
        ).filter(
            models.StudySession.user_id == current_user.id,
            models.QuestionResult.passed == False
        ).all()
        
        if len(failed_questions) < 4:
            return {"insight": "Keep studying! We need a few more data points to calculate your core weaknesses."}
        
        failed_texts = [q.question_text for q in failed_questions]
        
        response = client.embeddings.create(
            input=failed_texts,
            model="text-embedding-3-small"
        )
        embeddings = np.array([data.embedding for data in response.data])
        
        num_clusters = min(3, len(failed_texts) // 2)
        kmeans = KMeans(n_clusters=num_clusters, random_state=42, n_init="auto")
        kmeans.fit(embeddings)
        
        labels = kmeans.labels_
        largest_cluster_id = np.argmax(np.bincount(labels))
        
        worst_cluster_questions = [
            failed_texts[i] for i, label in enumerate(labels) if label == largest_cluster_id
        ]
        
        questions_block = "\n".join(worst_cluster_questions)
        system_prompt = f"""You are an analytical tutor. The student failed these specific questions:
        
        {questions_block}
        
        Identify the underlying academic concept they are struggling with. 
        Write a single, encouraging sentence diagnosing the exact weakness. 
        Example: "You consistently struggle with the mechanical principles of projectile motion."
        Return strictly in JSON: {{"diagnosis": "Your sentence here"}}"""
        
        completion = client.chat.completions.create(
            model="gpt-4o",
            response_format={"type": "json_object"},
            messages=[{"role": "system", "content": system_prompt}]
        )
        
        insight_data = json.loads(completion.choices[0].message.content)
        
        return {"insight": insight_data.get("diagnosis", "Review your recent incorrect answers to find patterns.")}
    
    except Exception as e:
        print(f"ML Clustering Error: {e}")
        raise HTTPException(status_code=500, detail="Failed to calculate weakness clusters.")
    
@app.websocket("/api/sessions/{session_id}/stream")
async def audio_stream_relay(websocket: WebSocket, session_id: int, db: Session = Depends(get_db)):
    await websocket.accept()
    
    headers = {
        "Authorization": f"Bearer {os.getenv('OPENAI_API_KEY')}",
        "OpenAI-Beta": "realtime=v1"
    }
    
    try:
        async with websockets.connect(OPENAI_REALTIME_URL, additional_headers=headers) as openai_ws:
            session_update = {
                "type": "session.update",
                "session": {
                    "input_audio_transcription": {
                        "model": "whisper-1"
                    }
                }
            }
            await openai_ws.send(json.dumps(session_update))
            
            async def receive_from_flutter():
                try:
                    while True:
                        data = await websocket.receive_bytes()
                        
                        event = {
                            "type": "input_audio_buffer.append",
                            "audio": base64.b64encode(data).decode("utf-8")
                        }
                        await openai_ws.send(json.dumps(event))
                except WebSocketDisconnect:
                    print("Flutter client disconnected.")
                    
            async def receive_from_openai():
                try:
                    while True:
                        response_str = await openai_ws.recv()
                        response = json.loads(response_str)
                        
                        if response.get("type") == "response.audio.delta":
                            audio_bytes = base64.b64decode(response["delta"])
                            await websocket.send_bytes(audio_bytes)
                            
                        elif response.get("type") == "conversation.item.input_audio_transcription.completed":
                            user_text = response.get("transcript", "")
                            await websocket.send_text(json.dumps({
                                "event": "user_transcript",
                                "text": user_text
                            }))
                            
                        elif response.get("type") == "response.audio_transcript.delta":
                            ai_delta = response.get("delta", "")
                            await websocket.send_text(json.dumps({
                                "event": "ai_transcript_delta",
                                "text": ai_delta
                            }))
                            
                except websockets.exceptions.ConnectionClosed:
                    print("OpenAI connection closed.")
                    
            await asyncio.gather(
                receive_from_flutter(),
                receive_from_openai()
            )
            
    except Exception as e:
        print(f"WebSocket Error: {e}")
    finally:
        try:
            await websocket.close()
        except RuntimeError:
            pass