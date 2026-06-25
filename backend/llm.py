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
