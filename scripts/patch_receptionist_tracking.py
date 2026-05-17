from pathlib import Path
import re

path = Path(__file__).resolve().parents[1] / "web-admin" / "receptionist" / "app.js"
text = path.read_text(encoding="utf-8")

new_render = '''function renderTracking(items) {
  const list = document.getElementById("tracking-list");
  if (!list) return;
  list.innerHTML = "";
  if (!items || !items.length) {
    list.innerHTML = '<motion class="card">No tracking data.</motion>';
    return;
  }

  const paged = paginateRows("tracking-list", items);
  paged.items.forEach((item) => {
    const card = document.createElement("motion");
    card.className = "card";
    const pct = Math.round((item.progress || 0) * 100);
    const canAct = item.status !== "COMPLETED";
    card.innerHTML = `
      <motion class="row-wrap" style="justify-content: space-between; align-items: flex-start;">
        <motion>
          <h4 style="margin: 0 0 4px;">${item.name}</h4>
          <p style="margin: 0 0 4px;">${item.service}</p>
          <p class="meta" style="margin: 0 0 4px; color: #c9b46a;">${item.schedule || ""}</p>
          ${item.barber ? `<p class="meta" style="margin: 0;">Barber: ${item.barber}</p>` : ""}
        </motion>
        <span class="tag ${item.status === "WAITING" ? "info" : item.status === "IN PROGRESS" ? "success" : "warning"}">${item.status}</span>
      </motion>
      <motion class="progress" style="margin-top: 10px; height: 8px;">
        <span style="width: ${pct}%; background: ${item.color};"></span>
      </motion>
      <motion class="row-wrap" style="margin-top: 6px; justify-content: space-between; align-items: center;">
        <span class="meta">${item.timeRemaining}${item.status === "IN PROGRESS" && pct > 0 ? ` • ${pct}%` : ""}</span>
        ${canAct ? `
          <motion class="row-wrap" style="gap: 6px;">
            <button type="button" class="btn secondary tracking-complete" title="Mark completed"
              data-kind="${item.kind}" data-appointment-id="${item.appointmentId || ""}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">✓ Complete</button>
            <button type="button" class="btn secondary tracking-cancel" title="Cancel / remove"
              data-kind="${item.kind}" data-appointment-id="${item.appointmentId || ""}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">✕ Cancel</button>
          </motion>
        ` : ""}
      </motion>
    `;
    list.appendChild(card);
  });

  const pager = paginationMarkup("tracking-list", paged.currentPage, paged.totalPages);
  if (pager) {
    list.insertAdjacentHTML("beforeend", pager);
  }
}
'''.replace('<motion', '<div').replace('</motion>', '</div>')

pattern = r"function renderTracking\(items\) \{[\s\S]*?\n\}\n\nfunction renderBarbers"
text, count = re.subn(pattern, new_render + "\n\nfunction renderBarbers", text, count=1)
if count != 1:
    raise SystemExit(f"renderTracking replace failed: {count}")

click_handler = '''
  if (target.classList.contains("tracking-complete")) {
    const name = target.dataset.name || "this client";
    const kind = target.dataset.kind || "appointment";
    const appointmentId = Number(target.dataset.appointmentId || "0");
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Mark ${name} as completed?`);
    if (!ok) return;
    try {
      if (kind === "walkin" && queueId > 0) {
        await postJson(apiUrl("receptionist.php"), { action: "updateWalkinStatus", queueID: queueId, status: "Completed" });
      } else if (appointmentId > 0) {
        await postJson(apiUrl("receptionist.php"), { action: "updateAppointmentStatus", appointmentID: appointmentId, status: "Completed" });
      }
      loadDashboard();
    } catch (error) {
      alert(error.message || "Unable to complete");
    }
    return;
  }

  if (target.classList.contains("tracking-cancel")) {
    const name = target.dataset.name || "this client";
    const kind = target.dataset.kind || "appointment";
    const appointmentId = Number(target.dataset.appointmentId || "0");
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Cancel ${name} and remove from tracking?`);
    if (!ok) return;
    try {
      if (kind === "walkin" && queueId > 0) {
        await postJson(apiUrl("receptionist.php"), { action: "updateWalkinStatus", queueID: queueId, status: "Cancelled" });
      } else if (appointmentId > 0) {
        await postJson(apiUrl("receptionist.php"), { action: "updateAppointmentStatus", appointmentID: appointmentId, status: "Cancelled" });
      }
      loadDashboard();
    } catch (error) {
      alert(error.message || "Unable to cancel");
    }
    return;
  }

'''

if "tracking-complete" not in text:
    text = text.replace(
        "  const appointmentId = target.dataset.appointmentId;",
        click_handler + "  const appointmentId = target.dataset.appointmentId;",
        1,
    )

path.write_text(text, encoding="utf-8")
print("Patched receptionist tracking")
