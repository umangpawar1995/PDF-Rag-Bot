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
