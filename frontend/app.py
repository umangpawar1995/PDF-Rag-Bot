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
