#!/bin/bash
echo "Starting PDF RAG Bot..."
uvicorn backend.api:app --host 0.0.0.0 --port 8000 --reload &
BACKEND_PID=$!
echo "Backend started (PID $BACKEND_PID)"
sleep 2
streamlit run frontend/app.py --server.port 8501 --server.address 0.0.0.0
kill $BACKEND_PID
