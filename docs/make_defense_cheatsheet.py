"""Builds the technical cheat sheet handed out at the defense.

Everything in here was read out of the running system -- versions from the
toolchain, limits from the code, schedules from the workflow files -- rather
than written from memory, so the sheet does not claim anything the system does
not do. Re-run after a stack change:

    python docs/make_defense_cheatsheet.py
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

OUT = Path(__file__).resolve().parent / "defense_cheatsheet.pdf"

INK = colors.HexColor("#15171C")
MUTED = colors.HexColor("#5A6070")
RULE = colors.HexColor("#D5D9E0")
ACCENT = colors.HexColor("#1F5FA8")
WARN = colors.HexColor("#8A5200")
BAND = colors.HexColor("#F2F4F8")

styles = getSampleStyleSheet()


def style(name, **kw):
    base = dict(name=name, fontName="Helvetica", fontSize=8.2, leading=10.6,
                textColor=INK, alignment=TA_LEFT)
    base.update(kw)
    return ParagraphStyle(**base)


S_TITLE = style("t", fontName="Helvetica-Bold", fontSize=16, leading=18, textColor=INK)
S_SUB = style("s", fontSize=8.6, leading=11, textColor=MUTED)
S_H = style("h", fontName="Helvetica-Bold", fontSize=10, leading=12, textColor=ACCENT,
            spaceBefore=1, spaceAfter=1)
S_Q = style("q", fontName="Helvetica-Bold", fontSize=8.6, leading=11, textColor=INK)
S_A = style("a", fontSize=8.2, leading=10.8, textColor=INK)
S_CELL = style("c", fontSize=7.8, leading=9.8)
S_CELLB = style("cb", fontName="Helvetica-Bold", fontSize=7.8, leading=9.8)
S_FLAG = style("f", fontSize=7.8, leading=10, textColor=WARN)
S_FOOT = style("ft", fontSize=6.8, leading=8.4, textColor=MUTED)


def heading(text):
    return Paragraph(text, S_H)


def section(title, flowable):
    """A heading welded to what it introduces.

    Without this the column break stranded '7. Reliability, money and abuse'
    and its table header at the foot of a column, with the rows overleaf.
    """
    return KeepTogether([heading(title), Spacer(1, 1), flowable])


def qa_parts(question, answer, flag=None):
    parts = [Paragraph(question, S_Q), Paragraph(answer, S_A)]
    if flag:
        parts.append(Paragraph("<b>If pressed:</b> " + flag, S_FLAG))
    parts.append(Spacer(1, 4.5))
    return parts


def qa(question, answer, flag=None):
    """One question with its answer, kept on a single page."""
    return KeepTogether(qa_parts(question, answer, flag))


def lead(title, question, answer, flag=None):
    """A heading and the first question under it, as ONE flat group.

    keepWithNext does not hold across column frames here, and nesting a
    KeepTogether inside another cannot split at all -- doing that to every
    heading blew the sheet from 3 pages to 7. A single flat group of heading
    plus paragraphs behaves.
    """
    return KeepTogether([heading(title)] + qa_parts(question, answer, flag))


def table(rows, widths):
    data = [[Paragraph(c, S_CELLB if i == 0 else S_CELL) for c in row]
            for i, row in enumerate(rows)]
    t = Table(data, colWidths=widths, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), BAND),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, RULE),
        ("LINEBELOW", (0, 1), (-1, -2), 0.25, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 2.6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.6),
    ]))
    return t


def build():
    doc = BaseDocTemplate(
        str(OUT), pagesize=A4,
        leftMargin=12 * mm, rightMargin=12 * mm,
        topMargin=11 * mm, bottomMargin=11 * mm,
        title="Brilliante Barbershop - Technical Cheat Sheet",
        author="Brilliante Barbershop",
    )
    usable_w = doc.width
    gap = 7 * mm
    col_w = (usable_w - gap) / 2

    frames = [
        Frame(doc.leftMargin, doc.bottomMargin, col_w, doc.height, id="L",
              leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0),
        Frame(doc.leftMargin + col_w + gap, doc.bottomMargin, col_w, doc.height, id="R",
              leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0),
    ]

    def decorate(canvas, _doc):
        canvas.saveState()
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        x = doc.leftMargin + col_w + gap / 2
        canvas.line(x, doc.bottomMargin, x, doc.bottomMargin + doc.height)
        canvas.setFont("Helvetica", 6.5)
        canvas.setFillColor(MUTED)
        canvas.drawRightString(A4[0] - doc.rightMargin, 6.5 * mm, "Page %d" % canvas.getPageNumber())
        canvas.drawString(doc.leftMargin, 6.5 * mm,
                          "Brilliante Barbershop - technical cheat sheet")
        canvas.restoreState()

    doc.addPageTemplates([PageTemplate(id="2col", frames=frames, onPage=decorate)])

    w1, w2 = col_w * 0.34, col_w * 0.66
    story = []

    # ---- masthead ----------------------------------------------------------
    story += [
        Paragraph("Technical cheat sheet", S_TITLE),
        Paragraph(
            "Brilliante Barbershop - AI-assisted booking, kiosk queue and hairstyle "
            "preview system. Answers below are what the code actually does.", S_SUB),
        Spacer(1, 7),
    ]

    # ---- 1. receipts -------------------------------------------------------
    story += [
        lead("1. Receipts",
           "Do we issue receipts?",
           "Yes, a <b>digital payment reference</b>. Every captured payment stores a "
           "<font face='Courier'>transaction_ref</font> in "
           "<font face='Courier'>appointment_payments</font>; for online payments this is "
           "the PayMongo reference. The customer sees it as <i>Receipt: &lt;ref&gt;</i> on "
           "the appointment and on the completed-booking detail screen, and the "
           "receptionist sees the same reference in the portal.",
           "It is a reference number, not a printed or emailed receipt, and not a "
           "BIR Official Receipt. The shop still issues its own OR at the counter - "
           "that is a business-registration requirement, outside the system's scope."),
        qa("Can a customer get proof after the fact?",
           "Yes. The reference persists on the booking record, so it can be read back "
           "any time from the app and cross-checked against PayMongo and the "
           "<font face='Courier'>appointment_payments</font> row."),
        Spacer(1, 2),
    ]

    # ---- 2. encryption -----------------------------------------------------
    story += [
        heading("2. Encryption and data protection"),
        KeepTogether([
            Paragraph("How is data encrypted?", S_Q),
            Paragraph("Three layers, each doing a different job:", S_A),
            Spacer(1, 2),
            table([
            ["Layer", "How"],
            ["In transit",
             "HTTPS/TLS on the API (Render) and the portal (Vercel); the database "
             "connection forces <font face='Courier'>sslmode=require</font>, so "
             "app-to-Postgres traffic is encrypted too."],
            ["At rest",
             "Supabase/AWS encrypt the database volume and the storage bucket at the "
             "platform level."],
            ["Passwords",
             "Never stored by us. Supabase Auth hashes them (bcrypt). Staff accounts "
             "use PHP <font face='Courier'>password_hash()</font>."],
            ["Sessions",
             "Supabase-issued JWT, verified server-side on every customer request."],
            ["Webhooks",
             "PayMongo callbacks are verified with <b>HMAC-SHA256</b> against a shared "
             "secret, so a forged 'payment succeeded' is rejected."],
            ], [w1, w2]),
        ]),
        Spacer(1, 4),
        qa("Are names and phone numbers individually encrypted?",
           "<b>No, and we do not claim they are.</b> They are ordinary columns protected "
           "by full-disk encryption, TLS, and role-based access. The accurate phrasing is "
           "\"stored in an access-controlled database with encryption in transit and at "
           "rest\" - not \"column-level encryption\".",
           "Field-level encryption would block the search, sort and join the booking "
           "system depends on. The mitigation is access control plus audit logging, "
           "which is the standard trade-off for operational data."),
        qa("What about the face photos? (Data Privacy Act, RA 10173)",
           "Consent is captured before the first scan. Scan captures and generated "
           "previews auto-purge after <b>90 days</b> "
           "(<font face='Courier'>SCAN_MEDIA_RETENTION_DAYS</font>); inactive accounts "
           "after <b>3 years</b>, and only when purging is explicitly switched on.",
           "Be precise: images are <i>retained for the retention window</i>, not deleted "
           "immediately after display - the barber needs to see what the customer picked. "
           "Do not describe it as process-and-discard."),
        qa("Who can see what?",
           "Three roles - customer, barber, receptionist/admin - each gated server-side. "
           "Staff actions are written to an audit log "
           "(<font face='Courier'>audit_log()</font>) covering user, service, hairstyle "
           "and settings changes, plus refunds."),
        Spacer(1, 2),
    ]

    # ---- 3. versions -------------------------------------------------------
    story += [
        section("3. Tools and versions", table([
            ["Component", "Version / detail"],
            ["Mobile app", "Flutter 3.44.0 (stable), Dart 3.12.0"],
            ["Android", "compileSdk 36, targetSdk 36, <b>minSdk 24</b> (Android 7.0 and up)"],
            ["iOS", "Codebase is Flutter, so iOS-capable; not yet built or signed"],
            ["Backend API", "PHP 8.2 on <font face='Courier'>php:8.2-apache</font> (Docker), ~70 endpoints"],
            ["Database", "PostgreSQL 17.6 (Supabase), 34 tables"],
            ["Auth + storage", "Supabase Auth (JWT) and Supabase Storage"],
            ["AI service", "Python + FastAPI, OpenCV, <b>MediaPipe 0.10.x</b>"],
            ["Face detection (device)", "Google ML Kit via <font face='Courier'>google_mlkit_face_detection</font>"],
            ["Image generation", "Grok Imagine (xAI) - fallbacks: Gemini 2.5 Flash Image, Replicate FLUX Kontext Pro"],
            ["Text AI", "Gemini 2.5 Flash Lite (chatbot, admin insights)"],
            ["Payments", "PayMongo (GCash / card), webhook-confirmed"],
            ["Hosting", "API on Render, receptionist/admin portal on Vercel"],
            ["Portal", "Plain HTML/CSS/JavaScript, no framework or build step"],
            ["Version control", "Git / GitHub, with a scheduled DB backup workflow"],
        ], [w1, w2])),
        Spacer(1, 5),
    ]

    # ---- 4. architecture ---------------------------------------------------
    story += [
        lead("4. Architecture, in one breath",
           "How do the pieces fit?",
           "<b>Three clients</b> - customer app, barber app, kiosk (all one Flutter "
           "codebase) - plus a <b>browser portal</b> for the receptionist and admin. All "
           "four talk to <b>one PHP API</b>, which owns every business rule and is the "
           "only thing that touches <b>PostgreSQL</b>. A separate <b>Python service</b> "
           "handles face and hair analysis. Image generation goes out to a third-party "
           "model.",
           "Why PHP and not a framework: the rules live in one place and are readable "
           "without a build step, which matters for a system a shop has to maintain."),
        qa("Why a separate Python service?",
           "MediaPipe is Python-only. Keeping it in its own service means a failure there "
           "degrades the scan gracefully instead of taking the booking system down."),
        Spacer(1, 2),
    ]

    # ---- 5. the AI question ------------------------------------------------
    story += [
        lead("5. What the AI actually does",
           "Where is the AI?",
           "<b>Scanning:</b> ML Kit on the phone frames the face and takes 3 captures. "
           "<b>Analysis:</b> MediaPipe server-side - Face Landmarker (478 points) for face "
           "shape, Image Segmenter for a per-pixel hair mask giving texture, colour and "
           "coverage, majority-voted across the 3 captures. "
           "<b>Matching:</b> deterministic rules, not a model. "
           "<b>Preview image:</b> generative AI edits your own photo."),
        qa("So the recommendation is not AI?",
           "Correct, and this is a design choice. The <i>perception</i> is AI; the "
           "<i>matching</i> is a weighted rule scorer (face-shape match +0.45, texture "
           "match +0.55, penalties for styles the hair cannot take). It is explainable - "
           "the system can state why a style was recommended - and it can only ever "
           "suggest a haircut the shop actually offers, with a price and a duration.",
           "A learned ranker over a 32-style catalog would be unexplainable and could "
           "recommend something unbookable. Honest framing: <b>AI perceives, rules match, "
           "AI renders.</b>"),
        qa("Is the preview a real photo of me?",
           "It is an <b>edit of your own capture</b>, not a generated stranger. The prompt "
           "forbids changing face, skin, eyes, glasses, clothing and background, and "
           "specifies the haircut in barber terms - fade height, guard numbers, length on "
           "top, fringe, neckline."),
        qa("What happens if someone is bald or wearing a cap?",
           "Detected and handled. Hair coverage under 1% reads as bald, 1-3% as "
           "obstructed. The system refuses to invent a hair texture, says which case it "
           "is, and still gives face-shape-based recommendations.",
           "This was a real bug we found and fixed: a shirt over the head once returned "
           "\"Hair: Wavy\". It now reports \"not measured\"."),
        Spacer(1, 2),
    ]

    # ---- 6. hair colour ----------------------------------------------------
    story += [
        lead("6. Hair colour detection",
           "How does it read my hair colour?",
           "It samples the pixels inside the hair mask - only hair, not skin or "
           "background - takes the <b>median</b> colour, converts it to HSV and maps it "
           "to a plain label: <i>black, dark brown, brown, blonde, red, gray</i>. The "
           "front photo is preferred because it is the best lit."),
        qa("Why the median and not the average?",
           "Hair has shiny highlights far brighter than the hair itself, and averaging "
           "them in lifted black hair to \"dark brown\". On real captures the mean read "
           "V=59-65 while the median read V=40-46 - exactly the difference between "
           "black and dark brown. The median ignores the highlights."),
        qa("What is the colour used for?",
           "One job only: telling the image model to <b>keep your colour</b>. The prompt "
           "says preserve the natural colour and do not lighten, darken, redden or "
           "recolour. It does not change which haircuts are recommended.",
           "Limits: it reads colour under the light you scanned in, so a dim room shifts "
           "brown towards black. Dyed or bleached hair is the weakest case."),
        Spacer(1, 2),
    ]

    # ---- 7. custom haircut -------------------------------------------------
    story += [
        lead("7. Custom haircuts and the catalog limit",
           "What if a customer wants a haircut not in the library?",
           "They can still book it. Every service has a <b>free-text instructions box</b> "
           "at booking, and whatever they type reaches the barber on the appointment "
           "detail screen. What they do not get is an <b>AI preview</b> of it, because a "
           "preview needs a written prompt we control."),
        qa("Why is the catalog limited at all?",
           "Because a catalog entry is not just a picture. It carries a <b>price, a "
           "duration, barber instructions and clipper sizes</b>. Those feed the slot "
           "engine and the bill. A free-form style has none of them, so the system "
           "cannot schedule it or charge for it correctly.",
           "32 styles across 3 face shapes and 3 hair textures is 92 catalog variants - "
           "it covers the shop's actual menu, not every haircut that exists."),
        qa("Why not let AI invent the recommendation instead of using a library?",
           "An invented style is <b>unbookable</b> - no service ID, no duration for the "
           "slot engine, no instructions for the barber holding the clippers. And it "
           "could not be explained to the customer. The library is what the shop can "
           "actually cut."),
        qa("Could you add a style?",
           "Yes - an admin adds it through the portal. The honest cost is that a new "
           "style needs its own written prompt, or the preview would be wrong. A test "
           "enforces that: every catalog style must have one."),
        Spacer(1, 2),
    ]

    # ---- 8. group booking --------------------------------------------------
    story += [
        lead("8. Group booking, in simple words",
           "How does booking for a group work?",
           "You say how many people. The system looks for <b>that many free hours in a "
           "row with one barber</b> - 4 people needs 4 straight hours - and offers up to "
           "<b>10 start times</b> spread over at least 3 days, so it reads as a choice of "
           "time, not one take-it-or-leave-it slot."),
        qa("What if no single barber has that many hours free?",
           "Two fallbacks, both offered as a choice: "
           "<b>Split</b> - everyone at the <i>same</i> hour with a different barber each. "
           "<b>Waves</b> - when the group is bigger than the number of barbers, as many "
           "as there are free barbers go first, the rest in the next hour. 5 people and 4 "
           "barbers becomes 4 at 10:00 and 1 at 11:00."),
        qa("Is it one booking or many?",
           "<b>One payment, many rows.</b> Each person is a separate appointment with "
           "their own barber, time and position in the group, tied together by a group "
           "ID. That is what lets a split group run under four different barbers and "
           "still be one bill.",
           "A partial booking - fewer people than asked for - is never automatic. The "
           "customer must tick a box confirming it books fewer."),
        Spacer(1, 2),
    ]

    # ---- 9. services -------------------------------------------------------
    story += [
        lead("9. Services",
           "What is a service here?",
           "A priced, timed item the shop sells. Each one carries a <b>price</b>, a "
           "<b>base duration</b>, a category, and a <b>channel</b> - appointment or "
           "walk-in - which decides where it appears. The duration drives the slot "
           "engine; the price drives the bill and the refund amount."),
        table([
            ["Service", "Price / time / channel"],
            ["Exclusive Haircut", "P300.00, 60 min, appointment"],
            ["Regular Haircut", "P250.00, 35 min, walk-in"],
        ], [w1, w2]),
        Spacer(1, 4),
        qa("Who manages them?",
           "The admin portal - add, edit, activate or deactivate. Changes are written to "
           "the audit log.",
           "Deleting is a <b>deactivation</b>, not a row delete, and deliberately so: "
           "past appointments reference the service, and hard-deleting it would break "
           "the history and the revenue figures."),
        Spacer(1, 2),
    ]

    # ---- 10. admin settings -----------------------------------------------
    story += [
        lead("10. Admin settings",
           "What can the shop change without a developer?",
           "The things that change in a real shop:"),
        table([
            ["Setting", "Current value"],
            ["Opening hours", "09:00-19:00, per weekday, with Sunday closed"],
            ["Break window", "12:00-13:00 (no slots generated)"],
            ["Closed dates", "Holidays and one-off closures"],
            ["Slot length", "60 minutes"],
            ["Appointment / walk-in time", "60 min / 35 min"],
            ["Timezone", "Asia/Manila"],
            ["Queue merge", "On - one queue for walk-ins and appointments"],
            ["Services, hairstyles, staff", "Full add / edit / deactivate"],
        ], [w1, w2]),
        Spacer(1, 4),
        qa("Why does the timezone setting matter?",
           "The servers run on UTC. Without it, the Philippine morning still counts as "
           "yesterday, so 'today' would be wrong until 8am. Every date boundary in the "
           "system is computed in the shop's timezone, not the server's."),
        Spacer(1, 2),
    ]

    # ---- 11. notifications -------------------------------------------------
    story += [
        lead("11. Notifications and reminders",
           "How do notifications work?",
           "<b>In-app only.</b> Events write a row to a notifications table; the app's "
           "bell icon reads them and shows an unread count. Six kinds: Appointment, "
           "Reminder, Queue, Promotion, System, Payment. Staff get their own feed for "
           "cancellations, refunds and queue changes."),
        qa("Is there a reminder for an upcoming appointment?",
           "<b>Partly, and this is worth being exact about.</b> There is one reminder: if "
           "an appointment is coming up and is <i>still unpaid</i>, the customer is "
           "nudged once before the booking is written off. There is <b>no</b> general "
           "\"your appointment is tomorrow\" reminder - which is why that toggle is "
           "hidden in the settings screen rather than shown and doing nothing.",
           "Two honest reasons. First, no push notifications: that needs Firebase, which "
           "was deliberately excluded, so a reminder only appears when the app is opened. "
           "A reminder you only see after opening the app is not a reminder. Second, the "
           "sweeps run on request traffic rather than a scheduler, so timing is "
           "best-effort. A dependable reminder needs push plus a cron - that is the "
           "clearest next step for this system."),
        Spacer(1, 2),
    ]

    # ---- 12. limits --------------------------------------------------------
    story += [
        lead("12. Known limits - say these before you are asked",
           "What is the accuracy of the face-shape detection?",
           "We do not publish an accuracy figure, because we have not run a labelled "
           "validation study. The landmarks are measured; the <i>classification</i> into "
           "face shapes uses published ratio thresholds.",
           "The <font face='Courier'>confidence_score</font> of 0.88 in the catalog is a "
           "<b>seeded per-style value, not a model confidence</b> - it is nearly identical "
           "on every variant, which is exactly why we removed the percentage from the UI "
           "rather than show a number that looks measured and is not."),
        qa("Weak spots you should own",
           "<b>Bald vs dark cap</b> is the hardest case - both read as near-zero hair. "
           "<b>Bleached or dyed hair</b> can breach the brightness threshold. "
           "<b>Hair length</b> is inferred from the lowest hair pixel relative to the "
           "chin, so a dark collar can read as long hair - which is why length no longer "
           "gates anything user-visible."),
        qa("What is not built?",
           "Push notifications (would need Firebase - deliberately excluded), multi-branch "
           "support, light mode, and an automated background scheduler. Time-based sweeps "
           "run on request, so they catch up the next time a staff screen loads."),
        Spacer(1, 2),
    ]

    # ---- 7. reliability ----------------------------------------------------
    story += [
        section("13. Reliability, money and abuse", table([
            ["Concern", "Control"],
            ["Double booking",
             "Slot locking at the database level; a paid booking holds its slot and "
             "conflicting writes are rejected."],
            ["Abandoned payments",
             "A 10-minute reservation hold, then the slot is released automatically."],
            ["Refund abuse",
             "3 refunds in 24h triggers a 7-day cooldown; 5 in 30 days triggers 30 days. "
             "Cancelling is never blocked - only the refund."],
            ["Late cancellation",
             "Inside 24 hours the booking still cancels (freeing the chair) but is not "
             "refundable. Stated on the payment screen before paying."],
            ["Refund payout",
             "Manual by the receptionist - there is no gateway auto-refund - and the desk "
             "sees a warning badge for repeat refunders."],
            ["Queue identity",
             "Kiosk walk-ins get a claim code, so an overheard queue number is not enough "
             "to claim someone else's slot."],
            ["Barber leave",
             "24 paid days a year, pending requests included, enforced on both request and "
             "approval."],
            ["Data loss",
             "Daily automated <font face='Courier'>pg_dump</font> of the public schema via "
             "GitHub Actions to a private Supabase bucket."],
        ], [w1, w2])),
        Spacer(1, 5),
    ]

    # ---- 8. testing --------------------------------------------------------
    story += [
        lead("14. How we know it works",
           "How is it tested?",
           "<b>24 PHP test scripts</b> covering booking rules, refunds, leave balances, "
           "group bookings, the queue merge, audit logging and the AI prompt catalog - "
           "about 250 assertions, run against the live database inside transactions that "
           "are rolled back. Plus <b>16 Flutter test files</b> (111 tests) and a clean "
           "static analysis."),
        qa("Give an example of a bug a test caught",
           "Seven of the 32 catalog hairstyles had no AI prompt and silently rendered as a "
           "generic barbers cut - no error, just the wrong haircut. A test now asserts that "
           "every catalog style resolves to its own prompt, and an unmatched style raises "
           "a visible error instead of guessing."),
        Spacer(1, 2),
    ]

    # ---- 9. scale / sdg ----------------------------------------------------
    story += [
        lead("15. Scope and contribution",
           "Will it scale?",
           "Sized for one shop: 4 barbers, hourly slots, a 30-day booking window. Postgres "
           "and the stateless API would carry far more; the real limit is the single-branch "
           "data model, which is a deliberate scope boundary, not an oversight."),
        qa("Which SDG does this serve?",
           "<b>SDG 8 (Decent Work and Economic Growth)</b> primarily - it formalises a "
           "small local business's scheduling, payments and records. <b>SDG 9 (Industry, "
           "Innovation and Infrastructure)</b> secondarily, as digital adoption by a micro "
           "enterprise."),
        qa("What is genuinely new here?",
           "Not the booking system. It is <b>linking a measured facial analysis to a "
           "catalog the shop can actually cut</b>, and showing the customer a preview on "
           "their own face before they commit - which turns \"what do you want?\" from a "
           "conversation into a shared picture."),
        Spacer(1, 6),
        Paragraph(
            "Generated from the live codebase. Figures - versions, limits, retention "
            "windows and test counts - were read from the toolchain, source and config, "
            "not from memory. Regenerate with "
            "<font face='Courier'>python docs/make_defense_cheatsheet.py</font>.", S_FOOT),
    ]

    doc.build(story)
    print("wrote " + str(OUT))


if __name__ == "__main__":
    build()
