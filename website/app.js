/* VenueVibe landing — live venue browser.
   Reads public data straight from Supabase (RLS-protected anon key, the same
   publishable key the mobile app ships with). Booking itself happens in the
   app for now; the full web app gets wired into this shell later. */

const SUPABASE_URL = "https://tlzhxzhrhuxqmtsuaaiz.supabase.co";
const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6" +
  "InRsemh4emhyaHV4cW10c3VhYWl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyNTg3" +
  "MzYsImV4cCI6MjA4NjgzNDczNn0.OCtkUnUzvksYS43fziutx7h496VDWmVgOPsdOBIschE";
const APP_URL = "https://github.com/fabtechonline/venuvibe/releases/latest";

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const state = {
  venues: [],
  categories: [],
  search: "",
  category: null, // category id or null = all
  sort: "name-asc",
};

const $ = (id) => document.getElementById(id);
const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
const rand = (n) => `R ${Number(n).toFixed(2).replace(/\.00$/, "")}`;

/* ── Load ───────────────────────────────────────────────────────────── */
async function load() {
  const today = new Date().toISOString().slice(0, 10);
  const [cats, resources] = await Promise.all([
    sb.from("categories").select("id,name").eq("is_active", true)
      .order("sort_order"),
    sb.from("resources")
      .select(`id,name,description,images,category_id,created_at,
               custom_selector_enabled,hourly_rate,
               tenants(name,city),categories(name),
               pricing_periods(id,start_date,end_date,is_active,hourly_rate),
               durations(period_id,label,minutes,price,is_active),
               reviews(rating)`)
      .eq("is_active", true),
  ]);
  if (cats.error || resources.error) {
    $("resultCount").textContent =
      "Could not load venues right now — please refresh.";
    console.error(cats.error || resources.error);
    return;
  }

  state.categories = cats.data;
  state.venues = resources.data.map((r) => {
    // The season covering today decides which tiers/prices to show.
    const season = (r.pricing_periods || []).find(
      (p) => p.is_active && p.start_date <= today && p.end_date >= today,
    );
    const tiers = (r.durations || [])
      .filter((d) => d.is_active && season && d.period_id === season.id)
      .sort((a, b) => a.minutes - b.minutes);
    const prices = tiers.map((t) => Number(t.price));
    const ratings = (r.reviews || []).map((x) => x.rating);
    return {
      id: r.id,
      name: r.name,
      description: r.description || "",
      image: (r.images || [])[0] || null,
      categoryId: r.category_id,
      category: r.categories?.name || "Venue",
      venue: r.tenants?.name || "",
      city: r.tenants?.city || "",
      createdAt: r.created_at,
      tiers,
      priceFrom: prices.length ? Math.min(...prices) : null,
      hourlyRate: r.custom_selector_enabled
        ? Number(season?.hourly_rate ?? r.hourly_rate) || null
        : null,
      rating: ratings.length
        ? ratings.reduce((a, b) => a + b, 0) / ratings.length
        : null,
      reviewCount: ratings.length,
    };
  });

  renderChips();
  renderStats();
  render();
}

/* ── Render ─────────────────────────────────────────────────────────── */
function renderStats() {
  const cities = new Set(state.venues.map((v) => v.city).filter(Boolean));
  const venues = new Set(state.venues.map((v) => v.venue).filter(Boolean));
  $("heroStats").innerHTML = `
    <div class="hero-stat"><b>${state.venues.length}</b><span>bookable spaces</span></div>
    <div class="hero-stat"><b>${venues.size}</b><span>venues</span></div>
    <div class="hero-stat"><b>${cities.size || 1}</b><span>cities</span></div>`;
}

function renderChips() {
  const counts = {};
  for (const v of state.venues) {
    counts[v.categoryId] = (counts[v.categoryId] || 0) + 1;
  }
  const chips = [
    `<button class="chip ${state.category ? "" : "active"}" data-cat="">All</button>`,
  ];
  for (const c of state.categories) {
    if (!counts[c.id]) continue;
    chips.push(
      `<button class="chip ${state.category === c.id ? "active" : ""}"
        data-cat="${c.id}">${esc(c.name)} · ${counts[c.id]}</button>`,
    );
  }
  $("categoryChips").innerHTML = chips.join("");
}

function filtered() {
  const q = state.search.trim().toLowerCase();
  let list = state.venues.filter(
    (v) =>
      (!state.category || v.categoryId === state.category) &&
      (!q ||
        [v.name, v.venue, v.category, v.city, v.description].some((s) =>
          s.toLowerCase().includes(q),
        )),
  );
  const by = {
    "name-asc": (a, b) => a.name.localeCompare(b.name),
    "name-desc": (a, b) => b.name.localeCompare(a.name),
    "price-asc": (a, b) => (a.priceFrom ?? 1e12) - (b.priceFrom ?? 1e12),
    "price-desc": (a, b) => (b.priceFrom ?? -1) - (a.priceFrom ?? -1),
    "rating-desc": (a, b) => (b.rating ?? -1) - (a.rating ?? -1),
    newest: (a, b) => b.createdAt.localeCompare(a.createdAt),
  }[state.sort];
  return list.sort(by);
}

function render() {
  const list = filtered();
  $("resultCount").textContent =
    `${list.length} of ${state.venues.length} spaces` +
    (state.search || state.category ? " (filtered)" : "");
  $("emptyState").hidden = list.length > 0;

  $("venueGrid").innerHTML = list
    .map((v) => {
      const img = v.image
        ? `style="background-image:url('${esc(v.image)}')"`
        : "";
      const price =
        v.priceFrom != null
          ? `${rand(v.priceFrom)} <small>from</small>`
          : v.hourlyRate
            ? `${rand(v.hourlyRate)} <small>/hour</small>`
            : `<small>price on request</small>`;
      const rating = v.rating
        ? `★ ${v.rating.toFixed(1)} <span class="none">(${v.reviewCount})</span>`
        : `<span class="none">No reviews yet</span>`;
      return `
      <article class="card" data-id="${v.id}" tabindex="0" role="button"
               aria-label="${esc(v.name)} details">
        <div class="card-img" ${img}>
          <span class="card-cat">${esc(v.category)}</span>
        </div>
        <div class="card-body">
          <div class="card-title">${esc(v.name)}</div>
          <div class="card-venue">${esc(v.venue)}${v.city ? " · " + esc(v.city) : ""}</div>
          <div class="card-foot">
            <div class="card-price">${price}</div>
            <div class="card-rating">${rating}</div>
          </div>
        </div>
      </article>`;
    })
    .join("");
}

/* ── Detail modal ───────────────────────────────────────────────────── */
function openModal(id) {
  const v = state.venues.find((x) => x.id === id);
  if (!v) return;
  const tierRows = v.tiers
    .map(
      (t) =>
        `<div class="tier-row"><span>${esc(t.label)}</span><b>${rand(t.price)}</b></div>`,
    )
    .join("");
  $("modalBody").innerHTML = `
    <div class="modal-img" ${v.image ? `style="background-image:url('${esc(v.image)}')"` : ""}></div>
    <div class="modal-body">
      <h3>${esc(v.name)}</h3>
      <div class="modal-meta">
        ${esc(v.venue)}${v.city ? " · " + esc(v.city) : ""} · ${esc(v.category)}
        ${v.rating ? ` · ★ ${v.rating.toFixed(1)} (${v.reviewCount})` : ""}
      </div>
      ${v.description ? `<p class="modal-desc">${esc(v.description)}</p>` : ""}
      ${tierRows ? `<div class="tier-list">${tierRows}</div>` : ""}
      ${
        v.hourlyRate
          ? `<div class="modal-note">⏱ Custom time ranges available at
             <b>${rand(v.hourlyRate)}/hour</b> — request your own slot and the
             venue approves before you pay.</div>`
          : ""
      }
      <div class="cta-row">
        <a class="btn btn-primary btn-lg" target="_blank" rel="noopener"
           href="${APP_URL}">Book in the app</a>
      </div>
      <p class="finePrint">Web booking is coming soon.</p>
    </div>`;
  $("modalBackdrop").hidden = false;
  document.body.style.overflow = "hidden";
}
function closeModal() {
  $("modalBackdrop").hidden = true;
  document.body.style.overflow = "";
}

/* ── Events ─────────────────────────────────────────────────────────── */
function syncSearch(value, fromHero) {
  state.search = value;
  if (fromHero) $("filterSearch").value = value;
  render();
  renderChips();
}

$("heroSearch").addEventListener("input", (e) => syncSearch(e.target.value, true));
$("heroSearchBtn").addEventListener("click", () => {
  syncSearch($("heroSearch").value, true);
  $("venues").scrollIntoView({ behavior: "smooth" });
});
$("heroSearch").addEventListener("keydown", (e) => {
  if (e.key === "Enter") $("heroSearchBtn").click();
});
$("filterSearch").addEventListener("input", (e) => syncSearch(e.target.value, false));
$("sortSelect").addEventListener("change", (e) => {
  state.sort = e.target.value;
  render();
});
$("categoryChips").addEventListener("click", (e) => {
  const chip = e.target.closest(".chip");
  if (!chip) return;
  state.category = chip.dataset.cat || null;
  renderChips();
  render();
});
$("venueGrid").addEventListener("click", (e) => {
  const card = e.target.closest(".card[data-id]");
  if (card) openModal(card.dataset.id);
});
$("venueGrid").addEventListener("keydown", (e) => {
  const card = e.target.closest(".card[data-id]");
  if (card && (e.key === "Enter" || e.key === " ")) {
    e.preventDefault();
    openModal(card.dataset.id);
  }
});
$("clearFilters").addEventListener("click", () => {
  state.search = "";
  state.category = null;
  $("heroSearch").value = "";
  $("filterSearch").value = "";
  renderChips();
  render();
});
$("modalClose").addEventListener("click", closeModal);
$("modalBackdrop").addEventListener("click", (e) => {
  if (e.target === e.currentTarget) closeModal();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeModal();
});

$("year").textContent = new Date().getFullYear();
load();
