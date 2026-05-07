import asyncio
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services import supabase_client, gemini_messenger

router = APIRouter()


class WebIncomingRequest(BaseModel):
    booking_id: str
    message: str


class HostSendRequest(BaseModel):
    conversation_id: str
    message: str


@router.post("/messages/web-incoming")
async def web_incoming(req: WebIncomingRequest):
    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, req.booking_id)
    if not guest:
        raise HTTPException(status_code=404, detail="Guest not found")

    conversation = await asyncio.to_thread(
        supabase_client.find_or_create_conversation,
        req.booking_id,
        guest["property_id"],
    )

    # Always log the guest message so the host can see it even in intervene mode
    await asyncio.to_thread(
        supabase_client.insert_message,
        conversation["id"],
        "guest",
        req.message,
    )

    if conversation.get("mode") == "intervene":
        await asyncio.to_thread(
            supabase_client.update_conversation,
            conversation["id"],
            ai_status="paused",
        )
        return {"status": "intervene_mode", "reply": None}

    property_data = await asyncio.to_thread(
        supabase_client.get_property_for_chat,
        guest["property_id"],
    )
    if not property_data or not property_data.get("master_json"):
        raise HTTPException(status_code=404, detail="Property data not found")

    # Fetch history before the current message was inserted so Gemini sees it
    # separately in the "Current Guest Message" field (matching blueprint template)
    history = await asyncio.to_thread(
        supabase_client.get_conversation_messages,
        conversation["id"],
    )
    # Exclude the message we just inserted (last item)
    history = history[:-1] if history else []

    first_result = await gemini_messenger.first_pass(
        master_json=property_data["master_json"],
        conversation_history=history,
        preferred_language=guest.get("preferred_language") or "not_set",
        guest_message=req.message,
    )

    if first_result.get("requires_web_search") and first_result.get("search_query"):
        reply = await gemini_messenger.second_pass_with_search(
            master_json=property_data["master_json"],
            conversation_history=history,
            preferred_language=guest.get("preferred_language") or "not_set",
            guest_message=req.message,
            search_query=first_result["search_query"],
        )
    else:
        reply = first_result["reply_to_guest"]

    requires_escalation = bool(first_result.get("requires_escalation"))

    await asyncio.to_thread(
        supabase_client.insert_message,
        conversation["id"],
        "ai",
        reply,
        sentiment=first_result.get("sentiment"),
        is_escalated_interaction=requires_escalation,
    )

    update_fields: dict = {"ai_status": "active"}
    if requires_escalation:
        update_fields["requires_attention"] = True
        update_fields["mode"] = "intervene"

    await asyncio.to_thread(
        supabase_client.update_conversation,
        conversation["id"],
        **update_fields,
    )

    return {
        "reply": reply,
        "requires_escalation": requires_escalation,
        "conversation_id": conversation["id"],
    }


@router.post("/messages/host-send")
async def host_send(req: HostSendRequest):
    await asyncio.to_thread(
        supabase_client.insert_message,
        req.conversation_id,
        "host",
        req.message,
    )
    await asyncio.to_thread(
        supabase_client.update_conversation,
        req.conversation_id,
        ai_status="paused",
    )
    return {"status": "sent"}
