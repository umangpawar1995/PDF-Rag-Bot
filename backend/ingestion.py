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
