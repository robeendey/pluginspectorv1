from __future__ import annotations

import math
import os
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont
from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Image as RLImage,
    KeepTogether,
    PageBreak,
    NextPageTemplate,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    Frame,
)
from reportlab.lib.utils import ImageReader


ROOT = Path("/Users/admin/Sites/pluginspector")
TMP_DIR = ROOT / "tmp" / "pdfs"
ASSET_DIR = TMP_DIR / "assets"
OUT_DIR = ROOT / "output" / "pdf"
OUT_PDF = OUT_DIR / "PluginSpector-Competitive-Audit.pdf"
WORK_PDF = TMP_DIR / "PluginSpector-Competitive-Audit.work.pdf"
HERO_PNG = ASSET_DIR / "cover-hero.png"
MAP_PNG = ASSET_DIR / "market-map.png"

FONT_REG = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_ROUNDED = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Supplemental/Courier New.ttf"

NAVY = colors.HexColor("#08111F")
NAVY_2 = colors.HexColor("#0B1730")
SLATE = colors.HexColor("#13223B")
SLATE_2 = colors.HexColor("#1A2D4A")
TEXT = colors.HexColor("#EDF4FF")
TEXT_DIM = colors.HexColor("#A9B6CF")
MINT = colors.HexColor("#6DE7C8")
MINT_2 = colors.HexColor("#BDF6E6")
TEAL = colors.HexColor("#45B8FF")
AMBER = colors.HexColor("#FFB44D")
PINK = colors.HexColor("#E67AFB")
RED = colors.HexColor("#FF6678")
GREEN = colors.HexColor("#77E08B")
GRID = colors.HexColor("#243955")


@dataclass
class ToolSnapshot:
    name: str
    kind: str
    best_for: str
    risk: str
    trust: int
    breadth: int
    safety: int
    openness: int
    notes: str


@dataclass
class CommunitySignal:
    title: str
    what_people_want: str
    why_it_matters: str
    color: colors.Color


def register_fonts() -> None:
    fonts = [
        ("ReportArial", FONT_REG),
        ("ReportArialBold", FONT_BOLD),
        ("ReportArialRounded", FONT_ROUNDED),
    ]
    for name, path in fonts:
        if os.path.exists(path):
            pdfmetrics.registerFont(TTFont(name, path))


def font_name(kind: str) -> str:
    mapping = {
        "regular": "ReportArial" if "ReportArial" in pdfmetrics.getRegisteredFontNames() else "Helvetica",
        "bold": "ReportArialBold" if "ReportArialBold" in pdfmetrics.getRegisteredFontNames() else "Helvetica-Bold",
        "rounded": "ReportArialRounded" if "ReportArialRounded" in pdfmetrics.getRegisteredFontNames() else "Helvetica-Bold",
        "mono": "Courier",
    }
    return mapping[kind]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [FONT_BOLD if bold else FONT_REG, "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"]
    if bold and os.path.exists(FONT_ROUNDED):
        candidates.insert(0, FONT_ROUNDED)
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except Exception:
                pass
    return ImageFont.load_default()


def ensure_dirs() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)


def blend_hex(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


def create_hero_image(path: Path) -> None:
    width, height = 1800, 1160
    base = Image.new("RGBA", (width, height), (8, 17, 31, 255))
    px = base.load()

    top = (10, 18, 34)
    bottom = (19, 45, 68)
    for y in range(height):
        t = y / max(height - 1, 1)
        color = blend_hex(top, bottom, t)
        for x in range(width):
            px[x, y] = (*color, 255)

    draw = ImageDraw.Draw(base)

    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse((90, 110, 730, 730), fill=(90, 230, 200, 76))
    g.ellipse((1120, 70, 1620, 610), fill=(77, 143, 255, 56))
    g.ellipse((740, 640, 1380, 1160), fill=(255, 180, 77, 34))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=68))
    base = Image.alpha_composite(base, glow)
    draw = ImageDraw.Draw(base)

    # Main product window.
    window = (190, 150, 1520, 940)
    draw.rounded_rectangle(window, radius=44, fill=(11, 23, 48, 240), outline=(109, 231, 200, 56), width=3)

    # Window title bar.
    draw.rounded_rectangle((190, 150, 1520, 222), radius=44, fill=(15, 29, 58, 255))
    draw.rectangle((190, 185, 1520, 222), fill=(15, 29, 58, 255))
    for idx, c in enumerate([(255, 96, 96), (255, 186, 77), (116, 231, 139)]):
        draw.ellipse((232 + idx * 32, 177, 254 + idx * 32, 199), fill=c)
    draw.rounded_rectangle((320, 172, 620, 204), radius=16, fill=(22, 43, 74, 255))
    draw.rectangle((640, 183, 1210, 193), fill=(62, 87, 128, 255))

    # Sidebar panel.
    sidebar = (226, 252, 560, 880)
    draw.rounded_rectangle(sidebar, radius=28, fill=(17, 33, 58, 255), outline=(36, 57, 84, 255), width=2)
    sidebar_rows = [
        (260, 300, 526, 346, (109, 231, 200)),
        (260, 364, 526, 410, (69, 184, 255)),
        (260, 428, 526, 474, (231, 122, 251)),
        (260, 492, 526, 538, (255, 180, 77)),
        (260, 556, 526, 602, (119, 224, 139)),
    ]
    for rect in sidebar_rows:
        draw.rounded_rectangle(rect[:4], radius=18, fill=(27, 48, 78, 255), outline=(46, 70, 104, 255), width=2)
        draw.ellipse((rect[0] + 16, rect[1] + 13, rect[0] + 36, rect[1] + 33), fill=rect[4])
        draw.rounded_rectangle((rect[0] + 52, rect[1] + 11, rect[0] + 180, rect[1] + 25), radius=7, fill=(144, 165, 198, 255))
        draw.rounded_rectangle((rect[0] + 52, rect[1] + 28, rect[0] + 126, rect[1] + 37), radius=4, fill=(76, 104, 146, 255))

    # Filter chips.
    chip_specs = [
        ((262, 650, 356, 690), MINT),
        ((370, 650, 464, 690), TEAL),
        ((262, 706, 412, 746), AMBER),
        ((428, 706, 510, 746), PINK),
    ]
    for rect, color in chip_specs:
        rgb = color_to_rgb255(color)
        draw.rounded_rectangle(rect, radius=18, fill=rgb + (50,), outline=rgb + (130,), width=2)

    # Detail panel.
    detail = (590, 252, 1456, 880)
    draw.rounded_rectangle(detail, radius=28, fill=(14, 29, 55, 255), outline=(40, 62, 90, 255), width=2)

    # Hero cards.
    cards = [
        ((628, 304, 860, 434), (109, 231, 200), "Trust-first"),
        ((894, 304, 1126, 434), (69, 184, 255), "Scan map"),
        ((1160, 304, 1392, 434), (231, 122, 251), "Cleanup"),
        ((628, 468, 1392, 612), (255, 180, 77), "Reconcile safely"),
    ]
    title_font = load_font(28, bold=True)
    small_font = load_font(16, bold=False)
    for idx, (rect, color, label) in enumerate(cards):
        x1, y1, x2, y2 = rect
        draw.rounded_rectangle(rect, radius=24, fill=(20, 38, 68, 255), outline=(*color, 255), width=2)
        draw.ellipse((x1 + 18, y1 + 18, x1 + 48, y1 + 48), fill=(*color, 255))
        draw.text((x1 + 66, y1 + 14), label, font=title_font, fill=(244, 250, 255, 255))
        if idx == 0:
            for j, w in enumerate([170, 140, 120]):
                yy = y1 + 72 + j * 18
                draw.rounded_rectangle((x1 + 18, yy, x1 + 18 + w, yy + 10), radius=5, fill=(109, 231, 200, 170))
        elif idx == 1:
            for j, w in enumerate([184, 124, 156, 108]):
                yy = y1 + 70 + j * 16
                draw.rounded_rectangle((x1 + 18, yy, x1 + 18 + w, yy + 9), radius=4, fill=(69, 184, 255, 165))
        elif idx == 2:
            for j, w in enumerate([172, 140, 96]):
                yy = y1 + 70 + j * 20
                draw.rounded_rectangle((x1 + 18, yy, x1 + 18 + w, yy + 12), radius=6, fill=(231, 122, 251, 150))
        else:
            # a simplified chart in the large card
            for j, h in enumerate([30, 60, 42, 90, 70, 112]):
                bx = x1 + 20 + j * 116
                draw.rounded_rectangle((bx, y2 - 36 - h, bx + 68, y2 - 36), radius=14, fill=(255, 180, 77, 180))
            draw.line((x1 + 18, y2 - 52, x2 - 18, y2 - 52), fill=(80, 104, 140, 255), width=2)

    # Floating mint status cluster.
    cluster = (1040, 650, 1400, 840)
    draw.rounded_rectangle(cluster, radius=26, fill=(16, 33, 58, 255), outline=(109, 231, 200, 120), width=2)
    for i, (label, color) in enumerate([("AU", MINT), ("VST3", TEAL), ("AAX", AMBER)]):
        cx = 1086 + i * 88
        rgb = color_to_rgb255(color)
        draw.rounded_rectangle((cx, 690, cx + 68, 732), radius=16, fill=rgb + (60,), outline=rgb + (170,), width=2)
        draw.text((cx + 16, 699), label, font=load_font(16, bold=True), fill=(240, 248, 255, 255))
    draw.text((1088, 756), "Local inventory. Safer cleanup. Clearer trust.", font=small_font, fill=(173, 190, 214, 255))
    draw.rounded_rectangle((1088, 798, 1324, 820), radius=11, fill=(109, 231, 200, 120))

    # Soft border glow.
    base = base.filter(ImageFilter.GaussianBlur(radius=0.2))
    base.save(path)


def create_market_map_image(path: Path) -> None:
    width, height = 1800, 1120
    bg = Image.new("RGBA", (width, height), (9, 16, 31, 255))
    draw = ImageDraw.Draw(bg)
    top = (9, 16, 31)
    bottom = (20, 41, 64)
    for y in range(height):
        t = y / max(height - 1, 1)
        color = blend_hex(top, bottom, t)
        draw.line((0, y, width, y), fill=(*color, 255))

    # Background glows.
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((60, 120, 640, 700), fill=(109, 231, 200, 70))
    gd.ellipse((1160, 80, 1700, 620), fill=(69, 184, 255, 52))
    gd.ellipse((740, 600, 1600, 1120), fill=(255, 180, 77, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(72))
    bg = Image.alpha_composite(bg, glow)
    draw = ImageDraw.Draw(bg)

    chart = (120, 130, 1660, 980)
    draw.rounded_rectangle(chart, radius=34, fill=(12, 24, 44, 235), outline=(54, 75, 108, 255), width=2)
    draw.text((172, 164), "Competitive Landscape", font=load_font(30, bold=True), fill=(242, 248, 255, 255))
    draw.text((172, 208), "Breadth / feature depth on the x-axis. Trust / local transparency on the y-axis.", font=load_font(17), fill=(172, 187, 214, 255))

    # Grid.
    gx0, gy0, gx1, gy1 = 210, 280, 1560, 900
    for x in range(gx0, gx1 + 1, 150):
        draw.line((x, gy0, x, gy1), fill=(36, 55, 80, 255), width=1)
    for y in range(gy0, gy1 + 1, 120):
        draw.line((gx0, y, gx1, y), fill=(36, 55, 80, 255), width=1)
    draw.line((gx0, gy1, gx1, gy1), fill=(83, 103, 134, 255), width=2)
    draw.line((gx0, gy0, gx0, gy1), fill=(83, 103, 134, 255), width=2)

    # Axes.
    draw.line((gx0 + 30, gy1 - 30, gx1 - 30, gy1 - 30), fill=(95, 115, 145, 255), width=3)
    draw.line((gx0 + 30, gy1 - 30, gx0 + 30, gy0 + 30), fill=(95, 115, 145, 255), width=3)
    draw.text((gx1 - 320, gy1 - 10), "More feature breadth", font=load_font(16, bold=True), fill=(170, 189, 214, 255))
    draw.text((gx0 + 38, gy0 + 10), "More trust / local control", font=load_font(16, bold=True), fill=(170, 189, 214, 255))

    # Quadrant labels.
    quad_font = load_font(17, bold=True)
    draw.text((gx0 + 40, gy0 + 52), "Trust-first\ninventory tools", font=quad_font, fill=(109, 231, 200, 230))
    draw.text((gx1 - 360, gy0 + 52), "Breadth-heavy\nall-in-ones", font=quad_font, fill=(255, 180, 77, 220))
    draw.text((gx0 + 40, gy1 - 120), "Niche DAW\nutilities", font=quad_font, fill=(173, 190, 214, 220))
    draw.text((gx1 - 340, gy1 - 120), "Platform suites\nwith databases", font=quad_font, fill=(231, 122, 251, 215))

    def bubble(x: int, y: int, label: str, color: tuple[int, int, int], w: int = 240) -> None:
        h = 68
        draw.rounded_rectangle((x, y, x + w, y + h), radius=20, fill=(18, 36, 64, 245), outline=(*color, 255), width=3)
        draw.ellipse((x + 16, y + 18, x + 42, y + 44), fill=(*color, 255))
        draw.text((x + 54, y + 17), label, font=load_font(19, bold=True), fill=(244, 250, 255, 255))

    # Tool placement.
    bubble(420, 410, "PluginSpector", (109, 231, 200))
    bubble(980, 500, "PlugPane", (69, 184, 255))
    bubble(1140, 630, "Plugin Station", (231, 122, 251), w=280)
    bubble(760, 350, "AAX Plugin Manager", (255, 180, 77), w=330)
    bubble(650, 560, "OwlPlug", (119, 224, 139))
    bubble(320, 280, "Logic Pro baseline", (221, 227, 237), w=300)

    # A small legend.
    legend = (1300, 160, 1580, 250)
    draw.rounded_rectangle(legend, radius=22, fill=(20, 38, 66, 235), outline=(54, 75, 108, 255), width=2)
    draw.text((1322, 180), "Interpretation", font=load_font(17, bold=True), fill=(244, 250, 255, 255))
    draw.text((1322, 207), "Right = broader workflow. Up = more trust/local control.", font=load_font(14), fill=(175, 190, 214, 255))

    bg.save(path)


def paragraph_style(name: str, font: str, size: int, leading: int, color=TEXT, align=TA_LEFT, space_after: int = 0) -> ParagraphStyle:
    return ParagraphStyle(
        name=name,
        fontName=font,
        fontSize=size,
        leading=leading,
        textColor=color,
        alignment=align,
        spaceAfter=space_after,
    )


def build_story() -> tuple[list, list]:
    styles = getSampleStyleSheet()
    title_style = paragraph_style("Title", font_name("rounded"), 28, 32, color=TEXT)
    cover_sub = paragraph_style("CoverSub", font_name("regular"), 12, 16, color=TEXT_DIM)
    section = paragraph_style("Section", font_name("bold"), 18, 22, color=TEXT, space_after=8)
    body = paragraph_style("Body", font_name("regular"), 10.2, 14, color=TEXT_DIM)
    body_bold = paragraph_style("BodyBold", font_name("bold"), 10.2, 14, color=TEXT)
    small = paragraph_style("Small", font_name("regular"), 8.4, 11, color=TEXT_DIM)
    tiny = paragraph_style("Tiny", font_name("regular"), 7.3, 9.2, color=TEXT_DIM)
    callout = paragraph_style("Callout", font_name("bold"), 11, 14, color=TEXT)
    mono = paragraph_style("Mono", font_name("mono"), 8.5, 10, color=TEXT_DIM)
    center = paragraph_style("Center", font_name("regular"), 10, 13, color=TEXT_DIM, align=TA_CENTER)

    snapshots = [
        ToolSnapshot(
            name="PluginSpector",
            kind="Local browser",
            best_for="Fast, transparent inventory of installed bundles.",
            risk="Not yet a cleanup or tagging powerhouse.",
            trust=5,
            breadth=2,
            safety=4,
            openness=2,
            notes="Current repo already covers scan, search, folder/vendor/format filters, reveal/open, CSV export, and bundle detail inspection.",
        ),
        ToolSnapshot(
            name="PlugPane",
            kind="All-in-one manager",
            best_for="Tags, duplicate cleanup, license vaulting, and broad plugin management.",
            risk="Community skepticism centers on trust, internet/database dependence, and scan correctness.",
            trust=2,
            breadth=5,
            safety=3,
            openness=1,
            notes="Strongest direct competitor on feature breadth.",
        ),
        ToolSnapshot(
            name="Plugin Station",
            kind="Paid suite",
            best_for="Update alerts, license keys, system profiles, and a full platform story.",
            risk="Subscription/perpetual pricing and a heavier ecosystem footprint.",
            trust=2,
            breadth=4,
            safety=3,
            openness=1,
            notes="Most comprehensive, but also the most platform-like.",
        ),
        ToolSnapshot(
            name="AAX Plugin Manager",
            kind="Pro Tools specialist",
            best_for="AAX-only grouping, notes, compare/export, and active/inactive folder workflows.",
            risk="Niche scope; not a cross-format answer.",
            trust=4,
            breadth=2,
            safety=4,
            openness=1,
            notes="Strong fit for Pro Tools power users.",
        ),
        ToolSnapshot(
            name="OwlPlug",
            kind="Open-source / cross-platform",
            best_for="Discovery, registries, DAW project analysis, and community-driven expansion.",
            risk="Less focused on cleanup and local-only privacy positioning.",
            trust=4,
            breadth=3,
            safety=3,
            openness=5,
            notes="Best open-source story in the set.",
        ),
        ToolSnapshot(
            name="Logic Pro baseline",
            kind="Built-in AU manager",
            best_for="Safe, native AU organization inside the DAW.",
            risk="AU-only and tied to Logic Pro.",
            trust=5,
            breadth=1,
            safety=3,
            openness=1,
            notes="The default baseline for Logic users, not a standalone manager.",
        ),
    ]

    community = [
        CommunitySignal(
            title="Trust and transparency",
            what_people_want="Signed builds, clear privacy posture, no surprise network behavior, and obvious installer requirements.",
            why_it_matters="If the app looks like it is talking to the internet or hiding its behavior, serious users back away fast.",
            color=MINT,
        ),
        CommunitySignal(
            title="Scan correctness",
            what_people_want="No false positives from preset/resource folders, and predictable handling of subfolders and nested bundles.",
            why_it_matters="The scanner is the product. If it is noisy, the whole experience feels unreliable.",
            color=TEAL,
        ),
        CommunitySignal(
            title="Cleanup safety",
            what_people_want="Format-aware keep rules, reversible quarantine, and clear delete/move semantics.",
            why_it_matters="People want to reclaim disk space without accidentally breaking a rig.",
            color=AMBER,
        ),
        CommunitySignal(
            title="Power-user memory",
            what_people_want="Tags, notes, publisher grouping, license import/export, and comparison across systems or DAWs.",
            why_it_matters="Once the inventory is clean, users want a database that helps them remember and act.",
            color=PINK,
        ),
    ]

    story = [NextPageTemplate("Cover")]

    # Page 1 - cover.
    story.append(Spacer(1, 0.05 * inch))
    cover_text = [
        Paragraph("<font color='#6DE7C8'>Competitive Audit</font>", paragraph_style("CoverEyebrow", font_name("bold"), 11, 13, color=MINT)),
        Spacer(1, 0.08 * inch),
        Paragraph("PluginSpector Competitive Audit", title_style),
        Spacer(1, 0.12 * inch),
        Paragraph("How to differentiate a local-first macOS plugin inventory app in a crowded market of managers, suites, and DAW-native tools.", paragraph_style("CoverLead", font_name("regular"), 13, 18, color=TEXT_DIM)),
        Spacer(1, 0.18 * inch),
        Table(
            [[
                chip("Local-first"),
                chip("Trust-aware"),
                chip("AAX-ready"),
            ]],
            colWidths=[1.15 * inch, 1.2 * inch, 1.1 * inch],
            style=TableStyle([("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0)]),
        ),
        Spacer(1, 0.22 * inch),
        Paragraph(
            "Current strength: a clean inventory browser with format, vendor, and folder views, search, export, and a transparent scan surface. The market opening is not “more features at any cost” - it is safer cleanup, better correctness, and a trust story people can believe.",
            paragraph_style("CoverCallout", font_name("bold"), 11, 15, color=TEXT),
        ),
    ]
    left_col = cover_text
    right_col = RLImage(str(HERO_PNG), width=5.0 * inch, height=3.22 * inch)
    story.append(
        Table(
            [[left_col, right_col]],
            colWidths=[2.85 * inch, 4.75 * inch],
            style=TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                    ("TOPPADDING", (0, 0), (-1, -1), 0),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                ]
            ),
        )
    )
    story.append(Spacer(1, 0.15 * inch))
    summary_box = Table(
        [
            [
                Paragraph("What this report covers", paragraph_style("CoverBoxTitle", font_name("bold"), 11, 13, color=TEXT)),
                Paragraph("What the field looks like, where PluginSpector already wins, where the market is noisy, and the strongest wedge for differentiation.", paragraph_style("CoverBoxBody", font_name("regular"), 10, 14, color=TEXT_DIM)),
            ]
        ],
        colWidths=[1.85 * inch, 5.85 * inch],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SLATE),
                ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#2B3E58")),
                ("LEFTPADDING", (0, 0), (-1, -1), 14),
                ("RIGHTPADDING", (0, 0), (-1, -1), 14),
                ("TOPPADDING", (0, 0), (-1, -1), 12),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 12),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ]
        ),
    )
    story.append(summary_box)
    story.append(Spacer(1, 0.17 * inch))
    story.append(
        Paragraph(
            "Prepared from current repo implementation, public vendor pages, and recurring community feedback on Gearspace and Reddit.",
            paragraph_style("CoverFooter", font_name("regular"), 9, 11, color=TEXT_DIM),
        )
    )
    story.append(NextPageTemplate("Body"))
    story.append(PageBreak())

    # Page 2 - market landscape.
    story.extend(section_header("Market Landscape", "The space splits into three product shapes: local inventory browsers, broad managers with databases and cleanup, and DAW-native or niche specialists."))
    story.append(RLImage(str(MAP_PNG), width=6.96 * inch, height=3.96 * inch))
    story.append(Spacer(1, 0.04 * inch))
    score_table = build_score_table(snapshots, body, tiny)
    story.append(score_table)
    story.append(Spacer(1, 0.08 * inch))
    story.append(
        Paragraph(
            "Qualitative scores are based on public product pages and recurring community feedback. They are meant to show positioning, not benchmark accuracy.",
            small,
        )
    )
    story.append(PageBreak())

    # Page 3 - competitor snapshots.
    story.extend(section_header("Competitor Snapshots", "Each tool owns a different wedge. The key is not to imitate all of them, but to pair one clear promise with the few flows users actually need."))
    snap_cards = [
        competitor_card(
            snapshots[1],
            body,
            body_bold,
            small,
            MINT,
            "Broadest feature set: tags, license vault, duplicate detection, enable/disable, and a large database.",
        ),
        competitor_card(
            snapshots[2],
            body,
            body_bold,
            small,
            PINK,
            "Heaviest product story: pricing, alerts, subscription/perpetual options, and a full ecosystem feel.",
        ),
        competitor_card(
            snapshots[3],
            body,
            body_bold,
            small,
            AMBER,
            "Deeply tailored to Pro Tools and AAX workflows, including notes, compare/export, and active/inactive folder management.",
        ),
        competitor_card(
            snapshots[4],
            body,
            body_bold,
            small,
            TEAL,
            "Best open-source angle, broad platform story, and long-term roadmap around discovery, registry, and project analysis.",
        ),
    ]
    story.append(grid_from_cards(snap_cards, 2))
    story.append(Spacer(1, 0.12 * inch))
    story.append(
        Paragraph(
            "<b>PluginSpector's current position:</b> a simpler, more transparent inventory browser. That is a good thing if the product is allowed to stay sharper than the suites.",
            body,
        )
    )
    story.append(PageBreak())

    # Page 4 - community signals.
    story.extend(section_header("Community Signals", "The most consistent feedback is surprisingly aligned: people want to trust the app, understand the scan, and avoid risky cleanup."))
    signal_cards = [
        signal_card(community[0], body, small),
        signal_card(community[1], body, small),
        signal_card(community[2], body, small),
        signal_card(community[3], body, small),
    ]
    story.append(grid_from_cards(signal_cards, 2))
    story.append(Spacer(1, 0.15 * inch))
    story.append(
        Table(
            [
                [
                    Paragraph("Takeaway", body_bold),
                    Paragraph("The communities are not asking for a bigger database first. They are asking for a clearer scanner, safer actions, and enough metadata to organize without making the tool feel heavy.", body),
                ]
            ],
            colWidths=[1.35 * inch, 5.70 * inch],
            style=TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#10213B")),
                    ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#253954")),
                    ("LEFTPADDING", (0, 0), (-1, -1), 12),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                    ("TOPPADDING", (0, 0), (-1, -1), 10),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ]
            ),
        )
    )
    story.append(PageBreak())

    # Page 5 - differentiation strategy.
    story.extend(section_header("How To Differentiate", "The wedge is not another all-in-one suite. It is a safer, more trustworthy audit layer that helps users understand and reconcile their plugin install."))
    strategy_cards = [
        strategy_card("Audit", "Scan exactly what matters and explain why each item exists.", "No false positives from nested resources or preset folders; transparent rules.", MINT),
        strategy_card("Reconcile", "Compare rigs and export clean inventories.", "Give users a way to move between machines, DAWs, and rebuilds without guesswork.", TEAL),
        strategy_card("Act safely", "Prefer quarantine, reversible changes, and explicit keep rules.", "Cleanup is only valuable if people trust the undo path.", AMBER),
        strategy_card("Remember", "Add lightweight notes, tags, and publisher grouping only where it helps.", "Metadata should support decisions, not turn the app into another suite.", PINK),
    ]
    story.append(grid_from_cards(strategy_cards, 2))
    story.append(Spacer(1, 0.15 * inch))
    story.append(
        Table(
            [
                [
                    Paragraph("Suggested positioning", paragraph_style("PosTitle", font_name("bold"), 11, 13, color=TEXT)),
                    Paragraph(
                        "PluginSpector is the trust-first plugin audit and reconciliation tool for macOS. It helps serious producers understand what is installed, what is duplicated, and what is safe to remove, without turning their computer into a cloud service or a giant app suite.",
                        body,
                    ),
                ]
            ],
            colWidths=[1.6 * inch, 5.45 * inch],
            style=TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#111F36")),
                    ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#2A4060")),
                    ("LEFTPADDING", (0, 0), (-1, -1), 14),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 14),
                    ("TOPPADDING", (0, 0), (-1, -1), 12),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 12),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ]
            ),
        )
    )
    story.append(PageBreak())

    # Page 6 - sources.
    story.extend(section_header("Sources And Notes", "Public vendor pages are used for feature claims. Community threads are used for demand signals and pain points."))
    sources = [
        "PluginSpector repo files: README.md, Sources/ContentView.swift, Sources/PluginScanner.swift",
        "PlugPane official site: https://www.plugpane.com/",
        "Plugin Station FAQ: https://www.pluginstation.app/faq",
        "AAX Plugin Manager resources: https://aaxpluginmanager.com/resources/",
        "AAX Plugin Manager privacy policy: https://aaxpluginmanager.com/privacy-policy-2/",
        "OwlPlug roadmap: https://owlplug.com/roadmap/",
        "Logic Pro product page: https://www.apple.com/logic-pro/",
        "Gearspace thread: PlugPane - Free MacOS Audio Plugin Manager (thread and related pages)",
        "Reddit thread: https://www.reddit.com/r/audioengineering/comments/1qjh4ko/i_made_a_completely_free_macos_app_for_managing/",
    ]
    for idx, src in enumerate(sources, start=1):
        story.append(
            Table(
                [[Paragraph(f"<b>{idx}.</b> {src}", body)]],
                colWidths=[7.15 * inch],
                style=TableStyle(
                    [
                        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#0F1D34") if idx % 2 else colors.HexColor("#10243F")),
                        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#233852")),
                        ("LEFTPADDING", (0, 0), (-1, -1), 10),
                        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                        ("TOPPADDING", (0, 0), (-1, -1), 8),
                        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                    ]
                ),
            )
        )
        story.append(Spacer(1, 0.08 * inch))
    story.append(
        Paragraph(
            "Note: scorecards and positioning notes are qualitative. They are intended for strategy discussion, not formal product benchmarking.",
            small,
        )
    )

    return story, [
        title_style,
        cover_sub,
        section,
        body,
        body_bold,
        small,
        tiny,
        callout,
        mono,
        center,
    ]


def chip(label: str) -> Table:
    style = TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#10233C")),
            ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#2B4F5C")),
            ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ]
    )
    return Table([[Paragraph(f"<font color='#DDF9F0'><b>{label}</b></font>", paragraph_style("Chip", font_name("bold"), 10, 12, color=TEXT))]], style=style)


def section_header(title: str, subtitle: str) -> list:
    return [
        Paragraph(title, paragraph_style("SectionTitle", font_name("rounded"), 20, 24, color=TEXT)),
        Spacer(1, 0.06 * inch),
        Paragraph(subtitle, paragraph_style("SectionSubtitle", font_name("regular"), 10.5, 14, color=TEXT_DIM)),
        Spacer(1, 0.16 * inch),
    ]


def build_score_table(snapshots: list[ToolSnapshot], body: ParagraphStyle, tiny: ParagraphStyle) -> Table:
    headers = ["Tool", "Trust", "Breadth", "Safety", "Openness", "Summary"]
    rows = [[Paragraph(f"<b>{h}</b>", body) for h in headers]]
    for snap in snapshots:
        rows.append(
            [
                Paragraph(f"<b>{snap.name}</b><br/><font size='8'>{snap.kind}</font>", body),
                score_cell(snap.trust),
                score_cell(snap.breadth),
                score_cell(snap.safety),
                score_cell(snap.openness),
                Paragraph(snap.notes, tiny),
            ]
        )
    tbl = Table(rows, colWidths=[1.35 * inch, 0.72 * inch, 0.76 * inch, 0.72 * inch, 0.78 * inch, 2.82 * inch], repeatRows=1)
    style = TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#17304A")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("ALIGN", (1, 1), (4, -1), "CENTER"),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("GRID", (0, 0), (-1, -1), 0.4, GRID),
            ]
        )
    for row_idx in range(1, len(rows)):
        bg = colors.HexColor("#0F1F34") if row_idx % 2 else colors.HexColor("#10243F")
        style.add("BACKGROUND", (0, row_idx), (-1, row_idx), bg)
        if snapshots[row_idx - 1].name == "PluginSpector":
            style.add("BACKGROUND", (0, row_idx), (-1, row_idx), colors.HexColor("#102E2A"))
    tbl.setStyle(style)
    return tbl


def score_cell(value: int) -> Table:
    colors_map = {1: "#4A2431", 2: "#6B372B", 3: "#7A5528", 4: "#2F664C", 5: "#1E6C58"}
    fill = colors.HexColor(colors_map.get(value, "#21354A"))
    return Table(
        [[Paragraph(f"<b>{value}</b>", paragraph_style("ScoreCell", font_name("bold"), 10, 12, color=TEXT, align=TA_CENTER))]],
        colWidths=[0.55 * inch],
        rowHeights=[0.28 * inch],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), fill),
                ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#38536E")),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        ),
    )


def competitor_card(snapshot: ToolSnapshot, body: ParagraphStyle, body_bold: ParagraphStyle, small: ParagraphStyle, accent: colors.Color, headline: str) -> Table:
    inner = [
        Paragraph(snapshot.name, paragraph_style(f"{snapshot.name}Title", font_name("bold"), 13, 16, color=TEXT)),
        Spacer(1, 0.04 * inch),
        Paragraph(f"<font color='{hex_color(accent)}'><b>{snapshot.kind}</b></font>", small),
        Spacer(1, 0.05 * inch),
        Paragraph(headline, body),
        Spacer(1, 0.05 * inch),
        Paragraph(f"<b>Best for:</b> {snapshot.best_for}", small),
        Spacer(1, 0.03 * inch),
        Paragraph(f"<b>Watch out:</b> {snapshot.risk}", small),
    ]
    return card(inner, accent, width=3.45 * inch)


def signal_card(signal: CommunitySignal, body: ParagraphStyle, small: ParagraphStyle) -> Table:
    inner = [
        Paragraph(signal.title, paragraph_style("SignalTitle", font_name("bold"), 13, 16, color=TEXT)),
        Spacer(1, 0.04 * inch),
        Paragraph(signal.what_people_want, body),
        Spacer(1, 0.05 * inch),
        Paragraph(f"<b>Why it matters:</b> {signal.why_it_matters}", small),
    ]
    return card(inner, signal.color, width=3.45 * inch)


def strategy_card(title: str, lead: str, detail: str, accent: colors.Color) -> Table:
    inner = [
        Paragraph(title, paragraph_style("StrategyTitle", font_name("rounded"), 15, 18, color=TEXT)),
        Spacer(1, 0.04 * inch),
        Paragraph(lead, paragraph_style("StrategyLead", font_name("bold"), 10.7, 13.5, color=TEXT)),
        Spacer(1, 0.04 * inch),
        Paragraph(detail, paragraph_style("StrategyDetail", font_name("regular"), 9.4, 12, color=TEXT_DIM)),
    ]
    return card(inner, accent, width=3.45 * inch)


def card(inner: list, accent: colors.Color, width: float) -> Table:
    return Table(
        [[inner]],
        colWidths=[width],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#0F1C31")),
                ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#253A56")),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 12),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 12),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LINEBEFORE", (0, 0), (0, -1), 3, accent),
            ]
        ),
    )


def hex_color(color: colors.Color) -> str:
    r, g, b = [int(round(c * 255)) for c in color.rgb()]
    return f"#{r:02X}{g:02X}{b:02X}"


def color_to_rgb255(color: colors.Color) -> tuple[int, int, int]:
    return tuple(int(round(c * 255)) for c in color.rgb())


def grid_from_cards(cards: list[Table], cols: int) -> Table:
    rows = []
    for i in range(0, len(cards), cols):
        row = cards[i : i + cols]
        if len(row) < cols:
            row = row + [Spacer(1, 0)] * (cols - len(row))
        rows.append(row)
        if i + cols < len(cards):
            rows.append([Spacer(1, 0.12 * inch)] * cols)
    return Table(
        rows,
        colWidths=[3.48 * inch] * cols,
        style=TableStyle(
            [
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        ),
    )


def build_doc(story: list) -> None:
    doc = BaseDocTemplate(
        str(WORK_PDF),
        pagesize=letter,
        leftMargin=0.7 * inch,
        rightMargin=0.7 * inch,
        topMargin=0.72 * inch,
        bottomMargin=0.65 * inch,
        title="PluginSpector Competitive Audit",
        author="Codex",
        subject="Competitive analysis and differentiation report",
    )

    cover_frame = Frame(
        doc.leftMargin,
        doc.bottomMargin,
        doc.width,
        doc.height,
        id="cover_frame",
        leftPadding=0,
        bottomPadding=0,
        rightPadding=0,
        topPadding=0,
    )
    body_frame = Frame(
        doc.leftMargin,
        doc.bottomMargin,
        doc.width,
        doc.height - 0.12 * inch,
        id="body_frame",
        leftPadding=0,
        bottomPadding=0,
        rightPadding=0,
        topPadding=0,
    )

    def cover_on_page(canvas, document):
        canvas.saveState()
        canvas.setFillColor(NAVY)
        canvas.rect(0, 0, letter[0], letter[1], stroke=0, fill=1)
        canvas.setFillColor(colors.Color(0.2, 0.5, 0.8, alpha=0.06))
        canvas.circle(90, 700, 250, stroke=0, fill=1)
        canvas.setFillColor(colors.Color(0.4, 0.9, 0.75, alpha=0.08))
        canvas.circle(520, 120, 220, stroke=0, fill=1)
        canvas.setFillColor(colors.Color(0.9, 0.7, 0.3, alpha=0.06))
        canvas.circle(560, 650, 170, stroke=0, fill=1)
        canvas.setFillColor(MINT)
        canvas.rect(0.7 * inch, 10.15 * inch, 2.2 * inch, 0.08 * inch, stroke=0, fill=1)
        canvas.setFillColor(TEXT_DIM)
        canvas.setFont(font_name("regular"), 8)
        canvas.drawString(0.7 * inch, 0.45 * inch, "Prepared for team review")
        canvas.drawRightString(letter[0] - 0.7 * inch, 0.45 * inch, "Page 1")
        canvas.restoreState()

    def body_on_page(canvas, document):
        canvas.saveState()
        canvas.setFillColor(NAVY)
        canvas.rect(0, 0, letter[0], letter[1], stroke=0, fill=1)
        canvas.setStrokeColor(GRID)
        canvas.setLineWidth(0.7)
        canvas.line(document.leftMargin, letter[1] - 0.48 * inch, letter[0] - document.rightMargin, letter[1] - 0.48 * inch)
        canvas.setFillColor(TEXT_DIM)
        canvas.setFont(font_name("regular"), 8.2)
        canvas.drawString(document.leftMargin, 0.35 * inch, "PluginSpector Competitive Audit")
        canvas.drawRightString(letter[0] - document.rightMargin, 0.35 * inch, f"Page {canvas.getPageNumber()}")
        canvas.restoreState()

    doc.addPageTemplates(
        [
            PageTemplate(id="Cover", frames=[cover_frame], onPage=cover_on_page),
            PageTemplate(id="Body", frames=[body_frame], onPage=body_on_page),
        ]
    )
    doc.build(story)


def main() -> None:
    register_fonts()
    ensure_dirs()
    create_hero_image(HERO_PNG)
    create_market_map_image(MAP_PNG)
    story, _styles = build_story()
    build_doc(story)
    OUT_PDF.write_bytes(WORK_PDF.read_bytes())


if __name__ == "__main__":
    main()
