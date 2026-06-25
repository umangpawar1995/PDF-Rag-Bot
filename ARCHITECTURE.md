# Architecture Guide

How every file in this project connects and why each decision was made.

---

## High-Level Flow

```
User uploads PDF
       │
       ▼
[FastAPI /upload]
       │
       ▼
pdf_extractor.py  ──► extracts text page by page (PyMuPDF)
       │
       ▼
ingestion.py      ──► splits into 500-token chunks with 50-token overlap
       │
       ▼
sentence-transformers ──► converts each chunk to a 384-dim vector (all-MiniLM-L6-v2)
       │
       ▼
ChromaDB          ──► stores vectors + metadata (source filename, page number) on disk
       │
       ▼
           [User asks a question]
                  │
                  ▼
       [FastAPI /query]
                  │
                  ▼
ingestion.py  ──► embeds question → searches ChromaDB → returns top-5 chunks + scores
                  │
                  ▼
llm.py        ──► builds prompt: system rules + conversation history + chunks + question
                  │
                  ▼
Groq API      ──► Llama 3.3 70B generates answer grounded in the chunks
                  │
                  ▼
frontend/app.py ──► displays answer + expandable source citations with relevance bars
```

---

## File-by-File Breakdown

### `backend/pdf_extractor.py`
**What it does:** Opens a PDF with PyMuPDF, reads it page by page, returns a list of `PageChunk` objects (text + source filename + page number).

**Why PyMuPDF:** Fastest PDF parser available in Python. Handles both digital PDFs and basic scanned text. Preserves page numbers which are used for source citations.

**Key output:** `list[PageChunk]` — each chunk carries metadata so answers can say "found on page 7 of snowflake_docs.pdf"

---

### `backend/ingestion.py`
**What it does:** Four responsibilities — ingest, search, list, delete.

| Function | What it does |
|---|---|
| `ingest_pdf()` | Takes a PDF path → extracts pages → splits into chunks → embeds → stores in ChromaDB |
| `similarity_search()` | Embeds a query → finds top-K closest chunks in ChromaDB → returns text + metadata + score |
| `list_indexed_docs()` | Reads ChromaDB metadata → returns unique filenames |
| `delete_doc()` | Finds all chunk IDs for a filename → deletes from ChromaDB |

**Chunking strategy:**
- Chunk size: 500 tokens (~375 words) — specific enough to be relevant, large enough for context
- Overlap: 50 tokens — prevents cutting a sentence mid-thought at chunk boundaries
- Splitter tries: paragraph breaks → sentence breaks → word breaks (in that order)

**Embedding model:** `all-MiniLM-L6-v2` from sentence-transformers
- Runs completely locally — no API key, no cost, no internet required after first download
- 90MB model, ~384 dimensions per vector
- Excellent quality for semantic search

**Vector store:** ChromaDB
- Persists to `chroma_db/` folder — survives app restarts
- Chosen over FAISS because FAISS is in-memory only (resets on restart)

---

### `backend/llm.py`
**What it does:** Manages the Groq LLM connection, conversation history, and prompt construction.

**Model:** `llama-3.3-70b-versatile` via Groq
- Free tier, no credit card required
- 70B parameter model — better reasoning than smaller models
- Groq's inference is the fastest available (often 500+ tokens/sec)

**Prompt engineering:**
```
[System rules]
  - Answer ONLY from provided context
  - Always cite source + page number
  - Say "I couldn't find it" if context is insufficient

[Last 4 conversation turns]   ← conversation memory

[Top-5 retrieved chunks]
  Each labeled: [Source 2: resume.pdf, Page 3 | Relevance: 0.82]

[User question]
```

**Conversation memory:** Stores last 10 turns per session in memory. The prompt includes last 4 turns so follow-up questions like "tell me more about that" work naturally. Session is identified by a UUID generated in the browser tab.

---

### `backend/comparator.py`
**What it does:** Takes two document filenames + a topic → searches each document independently → builds a structured comparison prompt → returns a markdown table + bullet summaries.

**Why a separate module:** Comparison needs a different retrieval strategy (filtering by source) and a different prompt template than regular chat.

---

### `backend/api.py`
**What it does:** FastAPI app exposing REST endpoints. Acts as the bridge between the Streamlit frontend and the backend logic.

| Endpoint | Method | What it does |
|---|---|---|
| `/upload` | POST | Accepts PDF file → saves temp → calls `ingest_pdf()` → deletes temp |
| `/query` | POST | Takes question + session_id + top_k → retrieves chunks → gets LLM answer |
| `/documents` | GET | Lists all indexed document filenames |
| `/documents/{filename}` | DELETE | Removes all chunks for that document |
| `/compare` | POST | Runs document comparison |
| `/history/{session_id}` | DELETE | Clears conversation memory for a session |

**Why FastAPI + Streamlit as separate processes:**
Streamlit reruns the entire Python script on every user interaction. If all logic lived inside Streamlit, the vector store and LLM connections would be re-initialized on every keypress. FastAPI stays alive as a persistent server — connections stay warm, ChromaDB stays open.

---

### `frontend/app.py`
**What it does:** The entire UI in one Streamlit file.

**Two tabs:**
1. **Chat tab** — chat history display, chat input, answer rendering, expandable source citations with relevance score bar (`████░░░░░░ 42%`)
2. **Compare tab** — two document selectors, topic input, comparison output rendered as markdown table

**Sidebar:**
- File uploader (accepts multiple PDFs at once)
- "Index PDFs" button — uploads each to `/upload` endpoint
- Indexed documents list — with per-document delete button
- Top-K slider — controls how many chunks are retrieved per query
- Clear conversation button

---

## Data Flow for a Query

```
1. User types: "What are the key skills in my resume?"

2. Streamlit POSTs to FastAPI /query:
   { question: "...", session_id: "abc-123", top_k: 5 }

3. FastAPI calls similarity_search("What are the key skills in my resume?", k=5)
   → sentence-transformers converts question to a 384-dim vector
   → ChromaDB finds 5 closest stored vectors (cosine similarity)
   → Returns chunks with scores like 0.87, 0.81, 0.74, 0.69, 0.61

4. FastAPI calls answer(question, chunks, history)
   → llm.py builds the prompt with system rules + history + chunks
   → Sends to Groq API (Llama 3.3 70B)
   → Gets back: "Based on your resume (Page 2), your key skills include..."

5. FastAPI returns:
   { answer: "...", sources: [{source: "resume.pdf", page: 2, score: 0.87}, ...] }

6. Streamlit renders the answer in a chat bubble
   → Sources shown in collapsible expander with visual score bars
```

---

## Why These Technology Choices

| Decision | Alternative Considered | Why We Chose This |
|---|---|---|
| Groq (free) | OpenAI GPT-4 (paid) | Free tier, faster, no credit card |
| sentence-transformers (local) | OpenAI embeddings (paid) | Free, no API key, works offline |
| ChromaDB (disk-persisted) | FAISS (in-memory) | Survives restarts, per-doc delete |
| FastAPI (separate server) | All-in-one Streamlit | Avoids re-init on every Streamlit rerun |
| LangChain text splitter | Custom splitting | Battle-tested overlap logic |
