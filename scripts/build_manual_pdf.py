#!/usr/bin/env python3
"""Render docs/MANUAL.md to docs/MANUAL.pdf.

Pipeline
  1. Python-Markdown  : Markdown -> HTML (tables, fenced code, Pygments highlighting)
  2. cover + TOC      : generated from the heading tree, links stay clickable in the PDF
  3. Google Chrome    : headless --print-to-pdf with a print stylesheet (A4, Korean fonts)
  4. PyMuPDF (opt.)   : page numbers in the footer and page numbers in the TOC
                        (two passes: render, measure heading pages, render again)

Usage: python3 scripts/build_manual_pdf.py [--md docs/MANUAL.md] [--pdf docs/MANUAL.pdf]
"""

import argparse
import datetime
import html
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown
from markdown.extensions.toc import slugify_unicode
from pygments.formatters import HtmlFormatter

PROJECT_DIR = Path(__file__).resolve().parent.parent

CSS = r"""
@page {
    size: A4;
    margin: 18mm 16mm 20mm 16mm;
}
:root {
    --text: #1d1f23;
    --muted: #5b6270;
    --line: #d5d9e0;
    --code-bg: #f4f6f9;
    --accent: #1f4e8c;
    --th-bg: #e9eef6;
}
html { font-size: 10.5pt; }
/* TrueType Nanum fonts embed as compact CID subsets; the CFF-based Noto CJK
   fonts make Chrome emit Type 3 glyph outlines and a ~5x larger PDF. */
body {
    font-family: "NanumBarunGothic", "NanumGothic", "Noto Sans CJK KR", sans-serif;
    color: var(--text);
    line-height: 1.55;
    word-break: keep-all;
    overflow-wrap: anywhere;
    margin: 0;
}
code, pre, kbd, samp {
    font-family: "DejaVu Sans Mono", "Liberation Mono", "NanumBarunGothic", monospace;
}

/* ---- cover ---- */
.cover {
    break-after: page;
    display: flex;
    flex-direction: column;
    justify-content: center;
    min-height: 240mm;
    border-left: 6px solid var(--accent);
    padding-left: 12mm;
}
.cover h1 { font-size: 26pt; margin: 0 0 6mm; line-height: 1.3; color: var(--accent); }
.cover .sub { font-size: 12.5pt; color: var(--muted); margin: 0 0 14mm; }
.cover dl { display: grid; grid-template-columns: 34mm 1fr; row-gap: 2mm; font-size: 10pt; }
.cover dt { color: var(--muted); }
.cover dd { margin: 0; }
.cover .note {
    margin-top: 16mm; padding: 4mm 5mm; background: var(--code-bg);
    border-radius: 3px; font-size: 9.5pt; color: var(--muted);
}

/* ---- toc ---- */
.toc { break-after: page; }
.toc h2 { border: 0; margin-top: 0; }
.toc ol { list-style: none; padding: 0; margin: 0; }
.toc li { margin: 0; }
.toc li.l2 { margin-top: 2.2mm; font-weight: 600; }
.toc li.l3 { padding-left: 7mm; font-weight: 400; font-size: 9.5pt; }
.toc a {
    display: flex; align-items: baseline; gap: 2mm;
    color: inherit; text-decoration: none;
}
.toc a .t { flex: 0 1 auto; }
.toc a .dots {
    flex: 1 1 auto; border-bottom: 1px dotted #9aa3b2; transform: translateY(-3px);
}
.toc a .p { flex: 0 0 auto; color: var(--muted); font-variant-numeric: tabular-nums; }

/* ---- headings ---- */
h1, h2, h3, h4 { break-after: avoid; line-height: 1.3; }
h2 {
    break-before: page;
    font-size: 18pt; color: var(--accent);
    border-bottom: 2px solid var(--accent);
    padding-bottom: 2mm; margin: 0 0 6mm;
}
h2.no-break { break-before: auto; }
h3 { font-size: 13.5pt; margin: 9mm 0 3mm; border-left: 4px solid var(--accent); padding-left: 3mm; }
h4 { font-size: 11pt; margin: 6mm 0 2mm; color: #2c3e60; }
p { margin: 0 0 3mm; text-align: justify; }
ul, ol { margin: 0 0 3mm; padding-left: 7mm; }
li { margin-bottom: 1mm; }
li > p { margin: 0; }
strong { font-weight: 700; }
a { color: var(--accent); }
hr { display: none; }

/* ---- blockquote ---- */
blockquote {
    margin: 3mm 0 4mm; padding: 3mm 5mm;
    border-left: 4px solid #d29a2a; background: #fdf7e9;
    color: #4a3b1a; break-inside: avoid;
}
blockquote p:last-child { margin-bottom: 0; }

/* ---- code ---- */
code {
    font-size: 0.88em; background: var(--code-bg);
    padding: 0.5px 3px; border-radius: 3px;
}
pre {
    background: var(--code-bg); border: 1px solid var(--line); border-radius: 4px;
    padding: 3mm 4mm; margin: 2mm 0 4mm;
    font-size: 8.4pt; line-height: 1.42;
    white-space: pre-wrap; overflow-wrap: anywhere;
    break-inside: auto;
}
pre code { background: none; padding: 0; font-size: inherit; }
.codehilite { margin: 0; }
.codehilite pre { margin: 2mm 0 4mm; }

/* ---- tables ---- */
table {
    border-collapse: collapse; width: 100%;
    margin: 2mm 0 5mm; font-size: 8.9pt; line-height: 1.4;
    break-inside: auto;
}
thead { display: table-header-group; }
tr { break-inside: avoid; }
th, td { border: 1px solid var(--line); padding: 1.3mm 2mm; vertical-align: top; text-align: left; }
th { background: var(--th-bg); font-weight: 700; }
td code, th code { font-size: 0.9em; white-space: pre-wrap; }

/* ---- misc ---- */
.pagebreak { break-before: page; }
img { max-width: 100%; }
"""


def split_front_matter(md_text: str):
    """Return (title, intro_quote_lines, body) with the Markdown TOC removed."""
    lines = md_text.splitlines()
    title = ""
    i = 0
    if lines and lines[0].startswith("# "):
        title = lines[0][2:].strip()
        i = 1
    quote = []
    while i < len(lines) and (lines[i].startswith(">") or not lines[i].strip()):
        if lines[i].startswith(">"):
            quote.append(lines[i][1:].strip())
        i += 1
    # Drop the hand-written "## 목차" section: it links to GitHub anchors which
    # do not match the ids generated here, so a TOC is rebuilt below.
    body = "\n".join(lines[i:])
    m = re.search(r"^## 목차\n.*?^---\s*$", body, flags=re.S | re.M)
    if m:
        body = body[: m.start()] + body[m.end():]
    return title, quote, body


def build_html(md_text: str, page_of: dict, *, subtitle: str, board: str,
               toolchain: str, source: str) -> str:
    title, quote, body = split_front_matter(md_text)

    md = markdown.Markdown(
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={
            "codehilite": {"guess_lang": False, "css_class": "codehilite", "noclasses": False},
            "toc": {"slugify": slugify_unicode, "toc_depth": "2-3"},
        },
        output_format="html5",
    )
    body_html = md.convert(body)

    # Heading tree from the toc extension: list of {level, id, name, children}.
    entries = []

    def walk(items):
        for it in items:
            entries.append((it["level"], it["id"], it["name"]))
            walk(it.get("children", []))

    walk(md.toc_tokens)

    toc_items = []
    for level, hid, name in entries:
        page = page_of.get(hid, "")
        toc_items.append(
            f'<li class="l{level}"><a href="#{hid}"><span class="t">{name}</span>'
            f'<span class="dots"></span><span class="p">{page}</span></a></li>'
        )

    today = datetime.date.today().isoformat()
    pyg_css = HtmlFormatter(style="default").get_style_defs(".codehilite")
    quote_html = "<br>".join(html.escape(q) for q in quote if q)
    quote_html = re.sub(r"`([^`]+)`", r"<code>\1</code>", quote_html)
    quote_html = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", quote_html)

    return f"""<!DOCTYPE html>
<html lang="ko"><head><meta charset="utf-8">
<title>{html.escape(title)}</title>
<style>{CSS}</style>
<style>{pyg_css}</style>
</head><body>
<section class="cover">
  <h1>{html.escape(title)}</h1>
  <p class="sub">{html.escape(subtitle)}</p>
  <dl>
    <dt>프로젝트</dt><dd>RISC-V/ (rtl, firmware, scripts, tb, constraints, docs)</dd>
    <dt>대상 보드</dt><dd>{html.escape(board)}</dd>
    <dt>Toolchain</dt><dd>{html.escape(toolchain)}</dd>
    <dt>생성일</dt><dd>{today}</dd>
    <dt>원본</dt><dd>{html.escape(source)} (scripts/build_manual_pdf.py로 생성)</dd>
  </dl>
  <div class="note">{quote_html}</div>
</section>
<section class="toc">
  <h2>목차</h2>
  <ol>{''.join(toc_items)}</ol>
</section>
{body_html}
</body></html>"""


def chrome_binary():
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
        path = shutil.which(name)
        if path:
            return path
    sys.exit("Google Chrome / Chromium is required for PDF rendering")


def render_pdf(html_path: Path, pdf_path: Path):
    cmd = [
        chrome_binary(), "--headless=new", "--disable-gpu", "--no-sandbox",
        f"--user-data-dir={html_path.parent / 'chrome-profile'}", "--no-first-run",
        "--no-pdf-header-footer", "--run-all-compositor-stages-before-draw",
        "--virtual-time-budget=10000",
        f"--print-to-pdf={pdf_path}", html_path.as_uri(),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def heading_pages(pdf_path: Path, md_text: str):
    """Map heading id -> printed page number using the PDF's link destinations."""
    import fitz  # PyMuPDF

    _, _, body = split_front_matter(md_text)
    md = markdown.Markdown(extensions=["toc"], extension_configs={
        "toc": {"slugify": slugify_unicode, "toc_depth": "2-3"}})
    md.convert(body)
    ids = []

    def walk(items):
        for it in items:
            ids.append(it["id"])
            walk(it.get("children", []))

    walk(md.toc_tokens)

    # The generated TOC (pages right after the cover) links to every heading in
    # document order. Chrome turns each href="#id" into an internal GOTO link
    # carrying the destination page, so reading those links in visual order
    # gives an exact id -> page mapping without any text matching.
    doc = fitz.open(pdf_path)
    targets = []
    for pno in range(1, len(doc)):
        # Chrome emits them as named destinations; PyMuPDF resolves the page.
        links = [l for l in doc[pno].get_links()
                 if l.get("kind") in (fitz.LINK_GOTO, fitz.LINK_NAMED) and "page" in l]
        if not links:
            break  # first body page without TOC links
        links.sort(key=lambda l: (round(l["from"].y0, 1), l["from"].x0))
        targets.extend(l["page"] + 1 for l in links)
        if len(targets) >= len(ids):
            break
    doc.close()
    if len(targets) < len(ids):
        print(f"warning: resolved {len(targets)} of {len(ids)} TOC targets", file=sys.stderr)
    return dict(zip(ids, targets))


def stamp_page_numbers(pdf_path: Path, title: str):
    import fitz

    doc = fitz.open(pdf_path)
    total = len(doc)
    font = None
    for cand in ("/usr/share/fonts/truetype/nanum/NanumBarunGothic.ttf",
                 "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
                 "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
        if Path(cand).exists():
            font = cand
            break
    for pno in range(total):
        if pno == 0:
            continue  # cover
        page = doc[pno]
        w, h = page.rect.width, page.rect.height
        label = f"{pno + 1} / {total}"
        kwargs = dict(fontsize=8, color=(0.36, 0.38, 0.44))
        if font:
            kwargs.update(fontname="body", fontfile=font)
        page.insert_text((w - 45 - 4 * len(label), h - 24), label, **kwargs)
        page.insert_text((45, h - 24), title, **kwargs)
    doc.subset_fonts()  # keep only the glyphs the footer uses, not the whole TTF
    doc.save(str(pdf_path) + ".tmp", garbage=3, deflate=True)
    doc.close()
    Path(str(pdf_path) + ".tmp").replace(pdf_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", default=PROJECT_DIR / "docs" / "MANUAL.md", type=Path)
    ap.add_argument("--pdf", default=PROJECT_DIR / "docs" / "MANUAL.pdf", type=Path)
    ap.add_argument("--keep-html", action="store_true", help="also write HTML beside the PDF")
    ap.add_argument("--subtitle", default="교육용 단일 사이클 RV32I 프로세서 · SoC · 펌웨어 toolchain · 빌드/시뮬레이션 스크립트 · Mini OS")
    ap.add_argument("--board", default="Digilent Nexys A7-100T (xc7a100tcsg324-1), Vivado 2022.1")
    ap.add_argument("--toolchain", default="riscv64-unknown-elf-gcc 9.3.0 (-march=rv32i -mabi=ilp32), Icarus Verilog")
    ap.add_argument("--footer-title", help="short title for the printed footer")
    args = ap.parse_args()

    md_text = args.md.read_text(encoding="utf-8")
    title = md_text.splitlines()[0].lstrip("# ").strip()
    try:
        source = str(args.md.resolve().relative_to(PROJECT_DIR))
    except ValueError:
        source = str(args.md)
    cover = dict(subtitle=args.subtitle, board=args.board,
                 toolchain=args.toolchain, source=source)

    try:
        import fitz  # noqa: F401
        have_fitz = True
    except ImportError:
        have_fitz = False
        print("PyMuPDF not installed: PDF will have no page numbers in TOC/footer", file=sys.stderr)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        html_path = tmp / "manual.html"
        # Pass 1: render without page numbers, measure where each heading lands.
        page_of = {}
        html_path.write_text(build_html(md_text, page_of, **cover), encoding="utf-8")
        render_pdf(html_path, args.pdf)
        if have_fitz:
            page_of = heading_pages(args.pdf, md_text)
            # Pass 2: same layout (TOC entries keep their line count), numbers filled in.
            html_path.write_text(build_html(md_text, page_of, **cover), encoding="utf-8")
            render_pdf(html_path, args.pdf)
            stamp_page_numbers(args.pdf, args.footer_title or title)
        if args.keep_html:
            shutil.copy(html_path, args.pdf.with_suffix(".html"))
    print(f"wrote {args.pdf}")


if __name__ == "__main__":
    main()
