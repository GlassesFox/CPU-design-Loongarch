import re
import sys

import fitz

PDF_PATH = r"k:\documents\LoongsonEdu\cdp_ede_local\doc\2023041918122813624.龙芯架构32位精简版参考手册_r1p03.pdf"


def main() -> int:
    doc = fitz.open(PDF_PATH)

    # First locate pages containing SYSCALL
    pat = re.compile(r"\bSYSCALL\b")
    hits = []
    for page_index in range(doc.page_count):
        text = doc.load_page(page_index).get_text("text")
        if pat.search(text):
            hits.append(page_index)
            if len(hits) >= 20:
                break

    print("pages_with_SYSCALL:", hits)
    if not hits:
        return 2

    # Print richer context from first couple pages
    for page_index in hits[:3]:
        text = doc.load_page(page_index).get_text("text")
        lines = text.splitlines()
        print("\n=== page", page_index, "===")
        for i, ln in enumerate(lines):
            if "SYSCALL" in ln:
                lo = max(0, i - 8)
                hi = min(len(lines), i + 9)
                for j in range(lo, hi):
                    print(lines[j])
                break

    # Try to parse an encoding bitstring row if present (similar to ERTN parsing used earlier)
    # Heuristic: find a line that begins with SYSCALL and contains a long 0/1 pattern.
    for page_index in hits:
        text = doc.load_page(page_index).get_text("text")
        for ln in text.splitlines():
            if not ln.strip().startswith("SYSCALL"):
                continue
            bits = re.findall(r"[01]", ln)
            if len(bits) == 32:
                b = "".join(bits)
                val = int(b, 2)
                print("\nSYSCALL_bits:", b)
                print("SYSCALL_hex : 0x%08X" % val)
                return 0

    print("\nDid not auto-parse a 32-bit encoding row; manual lookup needed from the context above.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
