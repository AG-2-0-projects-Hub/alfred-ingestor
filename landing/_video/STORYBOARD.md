# Veo storyboard, redo from scratch (SUPERSEDED 2026-10-04: the founder locked the repaired second iteration, see `locked/manifest.json`; kept for the seam rules and the clip 5 prompt)

Rules for every clip
- Same still closes one clip and opens the next (files in `frames/`). Both ends at rest: no moving hands, cup or doors at the first or last frame.
- One positive, physical description per clip. No "do not" sentences in the prompt (they plant the thing we want gone). The negative prompt lists objects only: text, logos, watermark, faces, extra people, crowd.
- The scene swap happens inside a flood of soft cream light in the middle of the clip. On the page a CSS flare sits over that moment, so any leftover ghosting is covered.
- Seams on the page: trim the last ~0.25 s of each clip (Veo overshoots its last frame), then crossfade 0.2 s to the exact still. Measured SSIM vs the still (1.0 = identical): first frames 0.93 to 0.98; last frames 0.73 to 0.94, rising to 0.93 to 0.999 about 0.25 s before the end.

Stills
- S1 `hero-courtyard-dusk`: stone courtyard at dusk, lit arched doorway with a hanging lantern, bougainvillea and clay pots. No person.
- S2 `anfitrion-terraza`: terrace at twilight, two hands around a ceramic cup resting on a weathered stone balustrade, phone beside it, glowing lantern at the right edge, violet hills.
- S3 `farol-pared`: rough plaster wall at night, one iron lantern glowing right of centre, left side quiet.
- S4 `huesped-llega`: same courtyard, one traveller seen from behind pulling a suitcase toward the lit archway.
- S5 `llave-en-puerta` (current): two dark wooden doors with a finger-wide strip of light between them, brass lock plate on the right door with a key fully in the keyhole, a hand entering from the right pinching the key's ring-shaped bow. The doors are slightly apart and the key is already in: that combination is why Veo invented "finish inserting, wiggle, pull out".
- S5' (new, to generate and approve first, ~$0.13): the same close-up with the doors fully closed (only a hairline of light along the seam), the key fully in the lock, the hand resting around the key's bow.
- S6 `bone`: flat #F4ECE0.

Clips (6 s, 16:9, no audio)
1. S1 to S2. The camera glides forward through the glowing arch, the golden light grows until the whole frame is soft glowing cream, then recedes and the camera arrives on the terrace where two hands already rest around the cup on the balustrade, a phone beside them, the lantern at the frame edge. The camera slows to a stop.
2. S2 to S3. The camera drifts toward the lantern beside the balustrade, the hands resting still around the cup as the camera moves. The lantern's light grows until the whole frame is soft glowing cream, then recedes to reveal the plaster wall at night with one iron lantern glowing and the left side quiet. The camera slows to a stop.
3. S3 to S4. The camera moves slowly toward the iron lantern, its light grows until the frame is soft glowing cream, then recedes and the camera arrives in the courtyard at dusk where a single traveller, seen from behind, pulls a suitcase toward the lit archway. The camera slows to a stop.
4. S4 to S5'. The camera follows the traveller forward into the stone archway, the walls sliding past, the glow ahead grows until the frame is soft glowing cream, then recedes and the camera arrives in front of two closed dark wooden doors with a hairline of golden light along the seam, a hand resting on the ring of a brass key already in the lock. The camera slows to a stop.
5. S5' to S6. Close on two closed doors (no gap), the key already in the lock, the hand on the key's ring. The hand turns the key a quarter turn clockwise in one smooth motion. Then the two doors swing slowly inward and warm light pours through, growing until the frame is soft, even, glowing cream.
   Order of events: closed, quarter turn, doors open. Nothing else.
   Fallback if any take wiggles the key: no turn, the hand rests and the doors swing inward.

Meaning of step 4 ("Entra"): you hold the keys. Alfred brings you to the door and you open it, with the whole conversation ready.

Workflow and spend
- Iterate cheap, finalise once. Hard cap $5 for the redo, at most two takes per clip, one batch at a time, spend reported before each batch.
- Open question to test (about $0.48): does the same prompt and seed give the same shot at 720p and at 1080p? If yes, iterate at 720p and render the approved take at 1080p. If no, iterate at the final resolution.
- Veo upscaling on Vertex (1080p and 4K from any video) was announced in April 2026 as private preview, "coming soon to public preview". Not confirmed for our project.
