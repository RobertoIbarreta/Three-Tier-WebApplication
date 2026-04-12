import { useEffect, useState } from "react";

const apiBase = import.meta.env.VITE_API_URL || "";

async function fetchItems() {
  const r = await fetch(`${apiBase}/api/items`);
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

async function addItem(title) {
  const r = await fetch(`${apiBase}/api/items`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

export default function App() {
  const [items, setItems] = useState([]);
  const [title, setTitle] = useState("");
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);

  const load = () =>
    fetchItems()
      .then(setItems)
      .catch((e) => setErr(String(e.message || e)))
      .finally(() => setLoading(false));

  useEffect(() => {
    load();
  }, []);

  async function onSubmit(e) {
    e.preventDefault();
    if (!title.trim()) return;
    setErr(null);
    try {
      await addItem(title.trim());
      setTitle("");
      await load();
    } catch (e) {
      setErr(String(e.message || e));
    }
  }

  return (
    <main>
      <h1>Three-tier demo</h1>
      <p className="muted">
        React UI → Go API on the ALB → RDS MySQL. Local dev: leave{" "}
        <code>VITE_API_URL</code> empty and use <code>npm run dev</code> (Vite
        proxies /api to port 8080).
      </p>
      {loading && <p>Loading…</p>}
      {!loading && (
        <>
          <ul>
            {items.map((it) => (
              <li key={it.id}>{it.title}</li>
            ))}
          </ul>
          <form onSubmit={onSubmit}>
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="New item"
              aria-label="New item"
            />
            <button type="submit">Add</button>
          </form>
        </>
      )}
      {err && <p className="err">{err}</p>}
    </main>
  );
}
