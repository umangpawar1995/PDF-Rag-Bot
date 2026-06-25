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
