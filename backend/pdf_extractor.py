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
