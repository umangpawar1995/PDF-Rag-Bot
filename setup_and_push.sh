#!/bin/bash
# Run this once on your local machine inside an empty folder.
# It creates the full project and pushes to GitHub.
# Usage: bash setup_and_push.sh

set -e

echo "=== PDF RAG Bot — project setup ==="

# ── Create folder structure ────────────────────────────────────────────────────
mkdir -p backend frontend

# ── .gitignore ─────────────────────────────────────────────────────────────────
cat > .gitignore << 'EOF'
.env
__pycache__/
*.pyc
*.pyo
venv/
.venv/
chroma_db/
uploads/
*.egg-info/
.DS_Store
EOF

# ── .env.example ───────────────────────────────────────────────────────────────
cat > .env.example << 'EOF'
GROQ_API_KEY=your_groq_api_key_here
EOF

# ── requirements.txt ───────────────────────────────────────────────────────────
cat > requirements.txt << 'EOF'
streamlit==1.35.0
fastapi==0.111.0
uvicorn==0.30.1
python-multipart==0.0.9
pymupdf==1.24.5
langchain==0.2.5
langchain-community==0.2.5
langchain-groq==0.1.6
sentence-transformers==3.0.1
chromadb==0.5.3
python-dotenv==1.0.1
httpx==0.27.0
EOF

# ── start.sh ───────────────────────────────────────────────────────────────────
cat > start.sh << 'EOF'
#!/bin/bash
echo "Starting PDF RAG Bot..."
uvicorn backend.api:app --host 0.0.0.0 --port 8000 --reload &
BACKEND_PID=$!
echo "Backend started (PID $BACKEND_PID)"
sleep 2
streamlit run frontend/app.py --server.port 8501 --server.address 0.0.0.0
kill $BACKEND_PID
EOF
chmod +x start.sh

# ── README.md ──────────────────────────────────────────────────────────────────
cat > README.md << 'EOF'
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
EOF

# ── backend/__init__.py ────────────────────────────────────────────────────────
touch backend/__init__.py

# ── backend/pdf_extractor.py ───────────────────────────────────────────────────
cat > backend/pdf_extractor.py << 'EOF'
import fitz  # PyMuPDF
from dataclasses import dataclass


@dataclass
class PageChunk:
    text: str
    source: str
    page: int


def extract_pages(pdf_path: str, filename: str) -> list[PageChunk]:
    """Extract text from every page of a PDF, returning one PageChunk per page."""
    doc = fitz.open(pdf_path)
    pages = []
    for page_num in range(len(doc)):
        text = doc[page_num].get_text().strip()
        if text:
            pages.append(PageChunk(text=text, source=filename, page=page_num + 1))
    doc.close()
    return pages
EOF

# ── backend/ingestion.py ───────────────────────────────────────────────────────
cat > backend/ingestion.py << 'EOF'
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma

from backend.pdf_extractor import extract_pages

CHROMA_DIR = "chroma_db"
COLLECTION_NAME = "pdf_rag"

_embeddings = None


def _get_embeddings() -> HuggingFaceEmbeddings:
    global _embeddings
    if _embeddings is None:
        _embeddings = HuggingFaceEmbeddings(
            model_name="all-MiniLM-L6-v2",
            model_kwargs={"device": "cpu"},
        )
    return _embeddings


def _get_vectorstore() -> Chroma:
    return Chroma(
        collection_name=COLLECTION_NAME,
        embedding_function=_get_embeddings(),
        persist_directory=CHROMA_DIR,
    )


def ingest_pdf(pdf_path: str, filename: str) -> int:
    """Chunk and embed a PDF, store in ChromaDB. Returns number of chunks added."""
    pages = extract_pages(pdf_path, filename)
    if not pages:
        return 0

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=500,
        chunk_overlap=50,
        separators=["\n\n", "\n", ". ", " ", ""],
    )

    docs = []
    metadatas = []
    for page in pages:
        chunks = splitter.split_text(page.text)
        for chunk in chunks:
            docs.append(chunk)
            metadatas.append({"source": page.source, "page": page.page})

    vs = _get_vectorstore()
    vs.add_texts(texts=docs, metadatas=metadatas)
    return len(docs)


def list_indexed_docs() -> list[str]:
    """Return unique filenames currently indexed in ChromaDB."""
    vs = _get_vectorstore()
    results = vs.get(include=["metadatas"])
    sources = {m["source"] for m in results["metadatas"] if m}
    return sorted(sources)


def delete_doc(filename: str) -> int:
    """Remove all chunks belonging to a specific document. Returns chunks deleted."""
    vs = _get_vectorstore()
    results = vs.get(include=["metadatas"])
    ids_to_delete = [
        results["ids"][i]
        for i, m in enumerate(results["metadatas"])
        if m.get("source") == filename
    ]
    if ids_to_delete:
        vs.delete(ids=ids_to_delete)
    return len(ids_to_delete)


def similarity_search(query: str, k: int = 5) -> list[dict]:
    """Return top-k chunks with relevance scores and metadata."""
    vs = _get_vectorstore()
    results = vs.similarity_search_with_relevance_scores(query, k=k)
    return [
        {
            "text": doc.page_content,
            "source": doc.metadata.get("source", "unknown"),
            "page": doc.metadata.get("page", 0),
            "score": round(float(score), 4),
        }
        for doc, score in results
    ]
EOF

# ── backend/llm.py ─────────────────────────────────────────────────────────────
cat > backend/llm.py << 'EOF'
import os
from dotenv import load_dotenv
from langchain_groq import ChatGroq
from langchain.schema import HumanMessage, SystemMessage

load_dotenv()

_llm = None


def _get_llm() -> ChatGroq:
    global _llm
    if _llm is None:
        _llm = ChatGroq(
            model="llama-3.3-70b-versatile",
            groq_api_key=os.environ["GROQ_API_KEY"],
            temperature=0.2,
            max_tokens=1024,
        )
    return _llm


SYSTEM_PROMPT = """You are a helpful AI assistant that answers questions strictly based on the provided PDF document context.

Rules:
- Answer ONLY from the provided context. Do not use outside knowledge.
- If the context does not contain enough information, say: "I could not find a clear answer in the uploaded documents."
- Always cite the source document and page number for every key claim.
- Be concise but complete. Use bullet points where appropriate.
- For comparison questions, use a structured table or side-by-side format."""


def build_prompt(query: str, chunks: list[dict], history: list[dict]) -> list:
    context_parts = []
    for i, chunk in enumerate(chunks, 1):
        context_parts.append(
            f"[Source {i}: {chunk['source']}, Page {chunk['page']} | Relevance: {chunk['score']}]\n{chunk['text']}"
        )
    context = "\n\n---\n\n".join(context_parts)

    history_text = ""
    for turn in history[-4:]:
        history_text += f"User: {turn['user']}\nAssistant: {turn['assistant']}\n\n"

    user_content = f"""Previous conversation:
{history_text}
Context from documents:
{context}

Question: {query}

Answer (cite sources):"""

    return [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=user_content),
    ]


def answer(query: str, chunks: list[dict], history: list[dict]) -> str:
    if not chunks:
        return "No relevant content found in the uploaded documents. Please upload PDFs and try again."
    messages = build_prompt(query, chunks, history)
    response = _get_llm().invoke(messages)
    return response.content
EOF

# ── backend/comparator.py ──────────────────────────────────────────────────────
cat > backend/comparator.py << 'EOF'
"""Document comparison mode — structured diff between two uploaded PDFs."""
from backend.ingestion import similarity_search
from backend.llm import _get_llm
from langchain.schema import HumanMessage, SystemMessage


COMPARE_SYSTEM = """You are a document comparison expert. You will be given content from two documents and a comparison topic.
Produce a clear, structured comparison in markdown table format followed by a brief summary of key differences and similarities."""


def compare_documents(doc_a: str, doc_b: str, topic: str) -> str:
    chunks_a = similarity_search(f"{topic} {doc_a}", k=4)
    chunks_b = similarity_search(f"{topic} {doc_b}", k=4)

    text_a = "\n".join(c["text"] for c in chunks_a if c["source"] == doc_a) or "No relevant content found."
    text_b = "\n".join(c["text"] for c in chunks_b if c["source"] == doc_b) or "No relevant content found."

    prompt = f"""Compare these two documents on the topic: "{topic}"

Document A — {doc_a}:
{text_a}

Document B — {doc_b}:
{text_b}

Provide:
1. A markdown comparison table with key attributes as rows and the two documents as columns.
2. A 3-5 bullet summary of the most important differences.
3. A 2-3 bullet summary of common ground."""

    messages = [
        SystemMessage(content=COMPARE_SYSTEM),
        HumanMessage(content=prompt),
    ]
    response = _get_llm().invoke(messages)
    return response.content
EOF

# ── backend/api.py ─────────────────────────────────────────────────────────────
cat > backend/api.py << 'EOF'
import os
import shutil
import tempfile
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from backend.ingestion import ingest_pdf, list_indexed_docs, delete_doc, similarity_search
from backend.llm import answer
from backend.comparator import compare_documents

app = FastAPI(title="PDF RAG Bot API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_history: dict[str, list[dict]] = {}


class QueryRequest(BaseModel):
    question: str
    session_id: str = "default"
    top_k: int = 5


class CompareRequest(BaseModel):
    doc_a: str
    doc_b: str
    topic: str


@app.post("/upload")
async def upload_pdf(file: UploadFile = File(...)):
    if not file.filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are accepted.")

    with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name

    try:
        chunks_added = ingest_pdf(tmp_path, file.filename)
    finally:
        os.unlink(tmp_path)

    return {"filename": file.filename, "chunks_indexed": chunks_added}


@app.get("/documents")
def get_documents():
    return {"documents": list_indexed_docs()}


@app.delete("/documents/{filename}")
def remove_document(filename: str):
    deleted = delete_doc(filename)
    if deleted == 0:
        raise HTTPException(status_code=404, detail="Document not found.")
    return {"deleted_chunks": deleted}


@app.post("/query")
def query(req: QueryRequest):
    chunks = similarity_search(req.question, k=req.top_k)
    history = _history.get(req.session_id, [])
    response = answer(req.question, chunks, history)

    history.append({"user": req.question, "assistant": response})
    _history[req.session_id] = history[-10:]

    return {
        "answer": response,
        "sources": [
            {"source": c["source"], "page": c["page"], "score": c["score"]}
            for c in chunks
        ],
    }


@app.post("/compare")
def compare(req: CompareRequest):
    result = compare_documents(req.doc_a, req.doc_b, req.topic)
    return {"comparison": result}


@app.delete("/history/{session_id}")
def clear_history(session_id: str):
    _history.pop(session_id, None)
    return {"cleared": True}
EOF

# ── frontend/app.py ────────────────────────────────────────────────────────────
cat > frontend/app.py << 'EOF'
import uuid
import httpx
import streamlit as st

API_BASE = "http://localhost:8000"

st.set_page_config(
    page_title="PDF RAG Bot",
    page_icon="📄",
    layout="wide",
    initial_sidebar_state="expanded",
)

if "session_id" not in st.session_state:
    st.session_state.session_id = str(uuid.uuid4())
if "messages" not in st.session_state:
    st.session_state.messages = []
if "docs" not in st.session_state:
    st.session_state.docs = []


def fetch_docs():
    try:
        r = httpx.get(f"{API_BASE}/documents", timeout=10)
        st.session_state.docs = r.json().get("documents", [])
    except Exception:
        st.session_state.docs = []


with st.sidebar:
    st.title("📄 PDF RAG Bot")
    st.caption("Ask anything across all your PDFs — powered by Llama 3.3 + ChromaDB")

    st.divider()
    st.subheader("Upload PDFs")
    uploaded = st.file_uploader(
        "Drop one or more PDF files", type=["pdf"], accept_multiple_files=True
    )
    if uploaded and st.button("Index PDFs", type="primary"):
        with st.spinner("Extracting, chunking & embedding…"):
            for f in uploaded:
                try:
                    resp = httpx.post(
                        f"{API_BASE}/upload",
                        files={"file": (f.name, f.read(), "application/pdf")},
                        timeout=120,
                    )
                    data = resp.json()
                    st.success(f"✅ {f.name} — {data.get('chunks_indexed', 0)} chunks indexed")
                except Exception as e:
                    st.error(f"❌ {f.name}: {e}")
        fetch_docs()

    st.divider()
    st.subheader("Indexed Documents")
    fetch_docs()
    if st.session_state.docs:
        for doc in st.session_state.docs:
            col1, col2 = st.columns([4, 1])
            col1.markdown(f"📎 `{doc}`")
            if col2.button("🗑", key=f"del_{doc}", help=f"Remove {doc}"):
                httpx.delete(f"{API_BASE}/documents/{doc}", timeout=10)
                st.success(f"Removed {doc}")
                fetch_docs()
                st.rerun()
    else:
        st.info("No documents indexed yet.")

    st.divider()
    top_k = st.slider("Chunks to retrieve (top-K)", 1, 10, 5)

    if st.button("🗑 Clear conversation"):
        st.session_state.messages = []
        httpx.delete(f"{API_BASE}/history/{st.session_state.session_id}", timeout=5)
        st.rerun()

tab_chat, tab_compare = st.tabs(["💬 Chat", "🔀 Compare Documents"])

with tab_chat:
    st.header("Chat with your PDFs")

    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg["role"] == "assistant" and msg.get("sources"):
                with st.expander("📚 Sources & Relevance Scores"):
                    for s in msg["sources"]:
                        score_bar = "█" * int(s["score"] * 10) + "░" * (10 - int(s["score"] * 10))
                        st.markdown(
                            f"**{s['source']}** — Page {s['page']}  \n"
                            f"Relevance: `{score_bar}` {s['score']:.2%}"
                        )

    if prompt := st.chat_input("Ask a question about your documents…"):
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Thinking…"):
                try:
                    resp = httpx.post(
                        f"{API_BASE}/query",
                        json={
                            "question": prompt,
                            "session_id": st.session_state.session_id,
                            "top_k": top_k,
                        },
                        timeout=60,
                    )
                    data = resp.json()
                    answer_text = data.get("answer", "No answer returned.")
                    sources = data.get("sources", [])
                except Exception as e:
                    answer_text = f"Error connecting to backend: {e}"
                    sources = []

            st.markdown(answer_text)
            if sources:
                with st.expander("📚 Sources & Relevance Scores"):
                    for s in sources:
                        score_bar = "█" * int(s["score"] * 10) + "░" * (10 - int(s["score"] * 10))
                        st.markdown(
                            f"**{s['source']}** — Page {s['page']}  \n"
                            f"Relevance: `{score_bar}` {s['score']:.2%}"
                        )

        st.session_state.messages.append(
            {"role": "assistant", "content": answer_text, "sources": sources}
        )

with tab_compare:
    st.header("Compare Two Documents")
    st.caption("Select two indexed PDFs and a topic — get a structured side-by-side analysis.")

    docs = st.session_state.docs
    if len(docs) < 2:
        st.warning("Upload and index at least 2 PDFs to use comparison mode.")
    else:
        col_a, col_b = st.columns(2)
        doc_a = col_a.selectbox("Document A", docs, key="cmp_a")
        doc_b = col_b.selectbox("Document B", [d for d in docs if d != doc_a], key="cmp_b")
        topic = st.text_input(
            "Comparison topic",
            placeholder="e.g. skills and experience, pricing model, data architecture…",
        )

        if st.button("Compare", type="primary") and topic:
            with st.spinner("Analysing and comparing…"):
                try:
                    resp = httpx.post(
                        f"{API_BASE}/compare",
                        json={"doc_a": doc_a, "doc_b": doc_b, "topic": topic},
                        timeout=90,
                    )
                    st.markdown(resp.json().get("comparison", "No comparison returned."))
                except Exception as e:
                    st.error(f"Error: {e}")
EOF

# ── Git init and push ──────────────────────────────────────────────────────────
git init
git add -A
git commit -m "Initial project scaffold — full PDF RAG bot with free stack"
git branch -M main
git remote add origin https://github.com/umangpawar1995/PDF-Rag-Bot.git
git push -u origin main

echo ""
echo "=== Done! ==="
echo "Repo pushed to: https://github.com/umangpawar1995/PDF-Rag-Bot"
echo ""
echo "Next steps:"
echo "  1. cp .env.example .env  — then add your GROQ_API_KEY from console.groq.com"
echo "  2. python -m venv venv && source venv/bin/activate"
echo "  3. pip install -r requirements.txt"
echo "  4. bash start.sh"
echo "  5. Open http://localhost:8501"
