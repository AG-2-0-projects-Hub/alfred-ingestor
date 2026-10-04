def lum(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def cr(a, b):
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)

T = {
 "H1 dark":  dict(canvas="#130F1C", surface="#1E1730", text="#F3EEF8", muted="#B3A6CC", handtx="#F0B24E", brandtx="#A98BEE", status="#8FC7A6", acc="#F0B24E", hand="#F0B24E", onhand="#130F1C"),
 "H1 light": dict(canvas="#F2EBDD", surface="#FBF8F1", text="#130F1C", muted="#5A4E70", handtx="#8A5A0B", brandtx="#5B3BA8", status="#2F6B4F", acc="#B06A06", hand="#F0B24E", onhand="#130F1C"),
 "H2 dark":  dict(canvas="#150B26", surface="#231440", text="#F4EFFA", muted="#B9A9D9", handtx="#F5B84C", brandtx="#B493F8", status="#8FD0AA", acc="#F5B84C", hand="#F5B84C", onhand="#150B26"),
 "H2 light": dict(canvas="#F5EDE0", surface="#FCF8F1", text="#1B1030", muted="#5B4C78", handtx="#86560A", brandtx="#5A33B5", status="#2D6A4C", acc="#B06A06", hand="#F5B84C", onhand="#1B1030"),
 "H3 dark":  dict(canvas="#1B0E1F", surface="#2B1832", text="#F6EEF4", muted="#C4A9C9", handtx="#F2B04B", brandtx="#CB9DEE", status="#92C9A4", acc="#F2B04B", hand="#F2B04B", onhand="#1B0E1F"),
 "H3 light": dict(canvas="#F3EADF", surface="#FBF6F0", text="#1B0E1F", muted="#66506B", handtx="#8A5A0B", brandtx="#7A3A9E", status="#2F6A4D", acc="#B06A06", hand="#F2B04B", onhand="#1B0E1F"),
 "H4 dark":  dict(canvas="#14121A", surface="#201D29", text="#F1EEF4", muted="#A8A2B8", handtx="#E8A33D", brandtx="#AE9BDB", status="#8FB39A", acc="#E8A33D", hand="#E8A33D", onhand="#14121A"),
 "H4 light": dict(canvas="#F2EBDD", surface="#FBF8F1", text="#14121A", muted="#5C586A", handtx="#8A5A0B", brandtx="#5E4A99", status="#3F6B52", acc="#B06A06", hand="#E8A33D", onhand="#14121A"),
}
for n, t in T.items():
    worst = 99
    bad = []
    for bg in ("canvas", "surface"):
        for fg in ("text", "muted", "handtx", "brandtx", "status"):
            v = cr(t[fg], t[bg])
            worst = min(worst, v)
            if v < 4.5:
                bad.append(f"{fg}/{bg} {v:.2f}")
    b = cr(t["onhand"], t["hand"])
    g = cr(t["acc"], t["canvas"])
    print(f"{n}: text/canvas {cr(t['text'], t['canvas']):.1f} worst-text-pair {worst:.1f} onhand/hand {b:.1f} acc/canvas {g:.1f} {'FAIL ' + ', '.join(bad) if bad else 'ok'}")
