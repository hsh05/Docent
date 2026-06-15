import os
import json
import base64
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from dotenv import load_dotenv
from openai import OpenAI

import models
from database import engine, get_db
from auth import get_password_hash, verify_password, create_access_token, get_current_user, ACCESS_TOKEN_EXPIRE_MINUTES
from datetime import timedelta

models.Base.metadata.create_all(bind=engine)

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

app = FastAPI(title="Docent API")

@app.post("/api/auth/register", status_code=status.HTTP_201_CREATED)
def register_user(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
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
        
        # Generaet questions
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