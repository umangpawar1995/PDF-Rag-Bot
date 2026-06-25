# Setup Guide

Everything you need to get PDF RAG Bot running locally from scratch.

---

## Prerequisites

- Python 3.10+ (you have 3.13.5 via Anaconda — this works)
- A free Groq API key — sign up at https://console.groq.com (no credit card)

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/umangpawar1995/PDF-Rag-Bot.git
cd PDF-Rag-Bot
```

---

## Step 2 — Install dependencies

You can use Anaconda's pip directly (no virtual env needed if you prefer):

```bash
pip install -r requirements.txt
```

What gets installed and why:

| Package | Version | Why |
|---|---|---|
| `streamlit` | 1.35.0 | Frontend UI framework |
| `fastapi` | 0.111.0 | Backend REST API |
| `uvicorn` | 0.30.1 | ASGI server to run FastAPI |
| `python-multipart` | 0.0.9 | Required for FastAPI file uploads |
| `pymupdf` | 1.25.5 | PDF text extraction (fastest available) |
| `langchain` | 0.2.5 | Orchestration — text splitting, chains |
| `langchain-community` | 0.2.5 | HuggingFace embeddings + ChromaDB integrations |
| `langchain-groq` | 0.1.6 | Groq LLM integration |
| `sentence-transformers` | 3.0.1 | Local embedding model (all-MiniLM-L6-v2) |
| `chromadb` | 0.5.3 | Vector database (persists to disk) |
| `python-dotenv` | 1.0.1 | Loads `.env` file for API keys |
| `httpx` | 0.27.0 | HTTP client used by Streamlit to call FastAPI |

> **Note:** PyMuPDF pinned to 1.25.5 (not 1.24.5) because 1.24.5 has no pre-built wheel for Python 3.13 and tries to compile from source, which fails on macOS ARM.

---

## Step 3 — Add your Groq API key

Open the `.env` file in the project root and replace the placeholder:

```
GROQ_API_KEY=your_groq_api_key_here
```

Get your key:
1. Go to https://console.groq.com
2. Sign up (free, no credit card)
3. Click "API Keys" → "Create API Key"
4. Paste it into `.env`

---

## Step 4 — Run the app

```bash
bash start.sh
```

This starts two processes:
- **FastAPI backend** on http://localhost:8000
- **Streamlit frontend** on http://localhost:8501

Open http://localhost:8501 in your browser.

---

## Step 5 — First use

1. Drag and drop one or more PDFs into the sidebar uploader
2. Click **"Index PDFs"** — wait for the green success message (this runs embedding)
3. Type a question in the chat input at the bottom
4. See the answer with source citations and relevance scores

---

## Troubleshooting

**"ModuleNotFoundError: No module named 'backend'"**
Run from the project root, not from inside the `backend/` folder:
```bash
cd PDF-Rag-Bot
bash start.sh   # correct
```

**"GROQ_API_KEY not found"**
Make sure your `.env` file exists in the project root (not `.env.example`) and contains the real key.

**First query is slow (~10-20 seconds)**
Normal — `sentence-transformers` downloads the `all-MiniLM-L6-v2` model (~90MB) on first run and caches it. Subsequent runs are fast.

**ChromaDB persistence**
Indexed PDFs are saved to the `chroma_db/` folder. This means if you stop and restart the app, your documents are still indexed — you don't need to re-upload.
