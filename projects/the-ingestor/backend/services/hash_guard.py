"""
File fingerprinting using the properties.file_fingerprints JSONB column.
Format: { filename: byte_size_as_int }

file_status() is a pure function — callers own the Supabase I/O.
"""


def file_status(fingerprints: dict, filename: str, size: int) -> str:
    """
    Returns:
      'skip'   — identical name AND size already recorded (REQ-10)
      'update' — same name, different size (REQ-11)
      'new'    — first time this filename appears for the property (REQ-12)
    """
    if filename not in fingerprints:
        return "new"
    return "skip" if fingerprints[filename] == size else "update"
