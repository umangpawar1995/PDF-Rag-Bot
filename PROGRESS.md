# Project Progress

Track of what's done, what's in progress, and what's coming next.

---

## Status: Phase 1 Complete — Ready to Run

---

## Done

### Core RAG Pipeline
- [x] PDF text extraction with page metadata (`backend/pdf_extractor.py`)
- [x] Text chunking — 500 token chunks, 50 token overlap (`backend/ingestion.py`)
- [x] Local embeddings — `all-MiniLM-L6-v2` via sentence-transformers, no API key needed
- [x] ChromaDB vector store — persists to `chroma_db/` folder, survives restarts
- [x] Semantic similarity search with relevance scores
- [x] Groq LLM integration — Llama 3.3 70B, free tier (`backend/llm.py`)
- [x] Grounded prompt engineering — LLM answers only from document context
- [x] Source citations in every answer — filename + page number

### Extra Features (beyond original spec)
- [x] Conversation memory — last 10 turns per session, last 4 included in prompt
- [x] Document comparison mode — structured markdown table diff between 2 PDFs (`backend/comparator.py`)
- [x] Per-document delete — remove individual docs from the index
- [x] Relevance score bars — visual `████░░░░░░ 74%` display per source chunk
- [x] Top-K slider — user controls how many chunks to retrieve (1–10)
- [x] Multi-session support — each browser tab gets its own conversation history via UUID

### Infrastructure
- [x] FastAPI REST backend with CORS (`backend/api.py`)
- [x] Streamlit frontend — Chat tab + Compare Documents tab (`frontend/app.py`)
- [x] `start.sh` — one command launches both backend + frontend
- [x] `.env` / `.env.example` for API key management
- [x] `.gitignore` — excludes `chroma_db/`, `.env`, `__pycache__`
- [x] `requirements.txt` — all dependencies pinned

### Documentation
- [x] `README.md` — overview, tech stack, setup, sample questions
- [x] `SETUP.md` — step-by-step setup with troubleshooting
- [x] `ARCHITECTURE.md` — how every file connects, data flow diagrams, decisions
- [x] `PROGRESS.md` — this file

---

## In Progress

- [ ] Add Groq API key to `.env` (waiting on user to get key from console.groq.com)
- [ ] First end-to-end test with real PDFs

---

## Up Next (Phase 2)

These are all planned — none are started yet.

### Functional improvements
- [ ] **Export answers** — download conversation as a `.md` or `.pdf` file
- [ ] **Keyword highlighting** — highlight the exact sentence in the source chunk that answered the question
- [ ] **Bulk upload via folder** — drag a folder of PDFs, ingest all at once
- [ ] **Re-index guard** — detect if a PDF was already indexed and skip re-embedding

### UI improvements
- [ ] **Dark mode** — Streamlit supports it natively via config
- [ ] **Progress bar during indexing** — show chunk count as it goes
- [ ] **Chat export button** — copy full conversation to clipboard
- [ ] **Source preview** — click a source citation to see the exact chunk text inline

### Infrastructure
- [ ] **Hugging Face Spaces deployment** — free public URL for portfolio
  - Push to HF Spaces repo
  - Add `GROQ_API_KEY` as a Space Secret
  - Done — public demo link

---

## Known Limitations

| Limitation | Impact | Fix (Phase 2) |
|---|---|---|
| Scanned PDFs (images) | Text won't extract | Add OCR via `pytesseract` |
| Very large PDFs (500+ pages) | Slow indexing | Add async ingestion with progress bar |
| Session history is in-memory | Clears on server restart | Move to Redis or SQLite |
| No auth | Anyone with the URL can use it | Add Streamlit's built-in auth |
| Single collection in ChromaDB | All users share the same index | Add per-user collections |

---

## Decisions Log

| Date | Decision | Reason |
|---|---|---|
| 2026-06-25 | Use PyMuPDF 1.25.5 not 1.24.5 | 1.24.5 has no Python 3.13 wheel, fails to compile on macOS ARM |
| 2026-06-25 | FastAPI as separate process from Streamlit | Prevents LLM/ChromaDB re-initialization on every Streamlit rerun |
| 2026-06-25 | ChromaDB over FAISS | FAISS is in-memory only — ChromaDB persists to disk across restarts |
| 2026-06-25 | sentence-transformers over OpenAI embeddings | Free, local, no API key, works offline after first model download |
| 2026-06-25 | Groq (Llama 3.3 70B) over OpenAI GPT-4 | Free tier, faster inference, no credit card |
