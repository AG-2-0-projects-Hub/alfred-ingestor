# Alfred — Terms of Service & Legal Considerations (Draft)

> **Status:** Working draft. NOT a final legal document.
> Items here are reminders and decision notes to inform the real ToS.
> Complete before public beta with real users.

---

## 1. Who agrees to what

### Host (the property owner / Alfred subscriber)
- The host is the primary contracting party with Alfred/the operator.
- They agree to the ToS at **sign-up**.
- Key clauses the host must explicitly accept:
  - Conversations with guests through Alfred may be used to improve the Alfred AI
    (training data, annotation rounds).
  - The host is responsible for informing their guests that an AI assistant will
    handle initial communication.
  - The host's property data (Airbnb listing + uploaded files) is processed to
    build a knowledge base. If the host deletes a property, property data is
    erased, but anonymised conversation history may be retained for AI training
    purposes.

### Guest (the person using the chat link)
- Guests do not create an Alfred account and do not sign the host ToS.
- **Two options (decide before beta):**
  1. **Covered by the booking** — the host's own house rules / rental agreement
     already covers communication with the property, and Alfred is just the
     medium. Simplest legally; common in STR industry.
  2. **Inline disclaimer on first chat open** — before the guest sends their
     first message, show a non-blocking one-liner:
     *"This chat is powered by Alfred AI. Conversations may be used to improve
     Alfred. [Learn more]"*
     Optional opt-out checkbox (default: opted in). If opt-out is ticked, the
     conversation is flagged and excluded from training runs.
  
  **Current lean:** Option 2 with a light-touch inline notice, no hard opt-out
  gate (which would break the flow). The opt-out flag just marks rows in the
  DB — excluded at query time during annotation.

---

## 2. Data retention & deletion

- **Property data** (scraped_markdown, ingested_markdown, master_json, files):
  deleted when a host removes a property. Storage files also removed.
- **Conversations + messages**: retained after property deletion for AI
  training. Anonymised: guests renamed to `Guest <X-yyy>` (first letter of
  name + first 3 chars of booking_id).
- **Training snapshot** (future): a frozen copy of master_json at last-training
  time, stored under the service role only, excluded from user-facing deletes.
  Gives annotation rounds the context of "what Alfred knew vs. what guests
  asked."
- **Retention period**: not yet defined. Decide before beta (suggested: 3 years
  then auto-purge, or indefinite with annual review).

---

## 3. Guest privacy

- Guest names and booking IDs are pseudonymised on property delete (see §2).
- Conversations may include personal details guests share voluntarily.
- This data is used only for improving Alfred; never sold or shared with third
  parties.
- If a guest explicitly requests erasure (GDPR Art. 17 / "right to be
  forgotten"), the operator should hard-delete their conversation rows.
  **TODO:** build a guest erasure endpoint (`DELETE /api/guest/:booking_id/data`)
  before EU users.

---

## 4. Intellectual property

- Uploaded PDFs, images, and documents: the host asserts they have the right to
  upload and process these files. Alfred is not responsible for third-party IP
  in uploaded files.
- Airbnb listing content: scraped with Firecrawl. Verify Airbnb ToS compliance
  before commercial launch.

---

## 5. AI disclaimers

- Alfred is an AI assistant, not a human. Guests should be informed of this
  (covered by the inline notice in §1).
- Alfred may make mistakes. The host remains responsible for the accuracy of
  information provided to guests.
- In emergency escalations, Alfred notifies the host but is not a substitute for
  real emergency services.

---

## 6. Open items (must resolve before beta)

- [ ] Decide host ToS format (click-wrap on sign-up vs. email agreement)
- [ ] Decide on guest inline notice vs. booking-covered consent
- [ ] Build opt-out flag on guest chat + exclude from training queries
- [ ] Define retention period for conversation data
- [ ] Build guest erasure endpoint (GDPR compliance)
- [ ] Review Airbnb scraping ToS compliance
- [ ] Have a lawyer review the final document

---

*Last updated: 2026-06-10 (session notes by Claude Code)*
