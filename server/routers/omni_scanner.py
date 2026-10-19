import asyncio
import re
from typing import Dict, List, Optional
from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field

omni_scanner_router = APIRouter(prefix="/api/v1/omni-scan", tags=["OmniScanner"])

# Per-client Drop-Oldest Queue Registry (Section 5.1 Max Capacity = 2)
_CLIENT_QUEUES: Dict[str, asyncio.Queue] = {}
MAX_QUEUE_SIZE = 2


class DocumentSummarizeRequest(BaseModel):
    ocr_text: Optional[str] = Field(default=None, description="Raw structured text from DocumentBatchOcrReader")
    text: Optional[str] = Field(default=None, description="Alternative field for raw text")
    max_sentences: int = Field(default=4, ge=1, le=8)

    @property
    def effective_text(self) -> str:
        return (self.ocr_text or self.text or "").strip()


class DocumentSummarizeResponse(BaseModel):
    document_type: str
    key_points: List[str]
    action_items: List[str]
    spoken_summary: str
    # Compatibility aliases for cross-version clients
    executive_summary: Optional[str] = None
    bullet_points: Optional[List[str]] = None
    sender_or_title: Optional[str] = None


async def verify_bearer_token(authorization: Optional[str] = Header(default=None)) -> str:
    # Allow authorization token verification while permitting test environments
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="1008 Policy Violation: Missing or invalid authentication token.",
        )
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="1008 Policy Violation: Empty token.",
        )
    return token


def _classify_and_summarize_document(ocr_text: str, max_sentences: int) -> DocumentSummarizeResponse:
    cleaned = re.sub(r"\s+", " ", ocr_text).strip()
    lower = cleaned.lower()

    # 1. Identify Document Category
    if any(k in lower for k in ["invoice", "amount due", "total due", "bill", "payment"]):
        doc_type = "Bill or Invoice"
    elif any(k in lower for k in ["rx", "prescription", "dosage", "tablet", "mg", "capsule"]):
        doc_type = "Medical Prescription"
    elif any(k in lower for k in ["receipt", "subtotal", "cash", "change due"]):
        doc_type = "Payment Receipt"
    else:
        doc_type = "Written Document"

    # 2. Extract Actionable Entities (Amounts, Dates, Dosages)
    amounts = re.findall(r"(?:USD|\$|EUR|€|GBP|£|INR|₹|Rs\.?)\s?\d+(?:[.,]\d{1,2})?", cleaned, re.IGNORECASE)
    dates = re.findall(
        r"\b(?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4})\b",
        cleaned,
        re.IGNORECASE,
    )
    dosages = re.findall(r"\b\d+\s?(?:mg|ml|tablet|tablets|capsule|capsules|times daily|daily)\b", cleaned, re.IGNORECASE)

    action_items: List[str] = []
    if amounts:
        action_items.append(f"Amounts mentioned: {', '.join(dict.fromkeys(amounts[:3]))}")
    if dates:
        action_items.append(f"Important dates: {', '.join(dict.fromkeys(dates[:3]))}")
    if dosages:
        action_items.append(f"Dosage instructions: {', '.join(dict.fromkeys(dosages[:3]))}")

    # 3. Extract Core Key Points
    raw_sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", cleaned) if len(s.strip()) > 3]
    key_points = raw_sentences[:max_sentences] if raw_sentences else [cleaned[:200]]

    # 4. Synthesize Blind-Friendly Spoken Output
    summary_parts = [f"Document Type: {doc_type}."]
    summary_parts.append("Key summary: " + " ".join(key_points))
    if action_items:
        summary_parts.append("Critical details: " + ". ".join(action_items) + ".")

    spoken_summary = " ".join(summary_parts)

    return DocumentSummarizeResponse(
        document_type=doc_type,
        key_points=key_points,
        action_items=action_items,
        spoken_summary=spoken_summary,
        executive_summary=spoken_summary,
        bullet_points=key_points,
        sender_or_title=doc_type,
    )


@omni_scanner_router.post("/summarize", response_model=DocumentSummarizeResponse)
async def summarize_document(
    payload: DocumentSummarizeRequest,
    client_token: str = Depends(verify_bearer_token),
) -> DocumentSummarizeResponse:
    """
    Non-blocking Drop-Oldest Queue Topology (maxsize=2) for low-latency OCR summarization.
    """
    queue = _CLIENT_QUEUES.setdefault(client_token, asyncio.Queue(maxsize=MAX_QUEUE_SIZE))

    # Drop oldest pending request immediately if queue is at capacity (>= 2)
    if queue.full():
        try:
            dropped_future = queue.get_nowait()
            if not dropped_future.done():
                dropped_future.cancel()
            queue.task_done()
        except asyncio.QueueEmpty:
            pass

    loop = asyncio.get_running_loop()
    task_future = loop.run_in_executor(
        None,
        _classify_and_summarize_document,
        payload.effective_text,
        payload.max_sentences,
    )
    await queue.put(task_future)

    try:
        result: DocumentSummarizeResponse = await task_future
        return result
    finally:
        if not queue.empty():
            try:
                queue.get_nowait()
                queue.task_done()
            except asyncio.QueueEmpty:
                pass
