# PDF RAG Bot

> Ask anything, across all your PDFs — in plain English. Powered entirely by free tools.

---

## Tech Stack (100% Free)

| Layer | Tool |
|---|---|
| LLM | Groq — Llama 3.3 70B (free API) |
| Embeddings | `sentence-transformers` — `all-MiniLM-L6-v2` (local, no API key) |
| Vector DB | ChromaDB (persists to disk) |
| PDF Parsing | PyMuPDF |
| Backend | FastAPI |
| Frontend | Streamlit |

---

## Features

- **Multi-PDF upload** — index as many PDFs as you want
- **Semantic search** — finds meaning, not just keywords
- **Source citations** — every answer shows which PDF and page it came from
- **Relevance scores** — visual bar showing how confident each retrieved chunk is
- **Conversation memory** — follow-up questions remember previous context
- **Document management** — view and delete indexed documents from the sidebar
- **Document comparison mode** — pick two PDFs, enter a topic, get a structured table comparison
- **Persistent storage** — ChromaDB persists to disk, PDFs stay indexed across restarts

---

## Setup

```bash
python -m venv venv
source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env          # then paste your GROQ_API_KEY inside
bash start.sh
```

Open **http://localhost:8501**

Get a free Groq API key at https://console.groq.com (no credit card needed)

---

## Project Structure

```
PDF-Rag-Bot/
├── backend/
│   ├── pdf_extractor.py   # PyMuPDF — extract text + page metadata
│   ├── ingestion.py       # Chunking, embedding, ChromaDB CRUD
│   ├── llm.py             # Groq LLM, prompt engineering, conversation memory
│   ├── comparator.py      # Document comparison mode
│   └── api.py             # FastAPI endpoints
├── frontend/
│   └── app.py             # Streamlit UI — chat tab + compare tab
├── chroma_db/             # Persisted vector store (git-ignored)
├── start.sh
├── requirements.txt
└── .env.example
```

---

## Sample Questions

After uploading a resume + job description:
- *"What skills from the resume match this job description?"*
- *"What is missing from the resume compared to the JD requirements?"*

After uploading Snowflake docs:
- *"How does Snowflake handle incremental loads?"*
- *"What is the difference between a dynamic table and a materialized view?"*
