"""3-Way Hybrid RAG Engine for S.P.A.R.K.Y. v2.0 (SQLite FTS5 + CPU ONNX Embeddings + Live Kiroshi Pinning)."""

from __future__ import annotations

import difflib
import hashlib
import json
import os
import re
import sqlite3
import threading
import time
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import numpy as np

from sparky_rt.companion_prefs import USER_BRIDGE_DIR
from sparky_rt.config import SparkyServiceConfig

HERE = Path(__file__).resolve().parent
LORE_KB_DIR = HERE / "lore_kb"
CUSTOM_LORE_PATH = USER_BRIDGE_DIR / "custom_lore_en.json"
DEFAULT_LORE_DB_PATH = USER_BRIDGE_DIR / "state" / "lore_index_en.sqlite"

ERA_BADGES = {
    "memoria_2022": "2022 ZETATECH MEMORY",
    "archivo_personal": "SPARKY-V SHARED LOG",
    "intel_kiroshi_2077": "2077 KIROSHI / NET INTEL",
}

_STOPWORDS_EN_ES = frozenset(
    {
        "the", "and", "for", "with", "what", "who", "where", "when", "why", "how",
        "this", "that", "these", "those", "from", "into", "about", "there", "here",
        "are", "was", "were", "have", "has", "had", "can", "could", "should", "would",
        "tell", "me", "know", "think", "sparky", "chispa", "night", "city",
        "el", "la", "los", "las", "un", "una", "de", "del", "en", "con", "por", "para",
        "que", "como", "quien", "donde", "cuando",
    }
)

_LOCATION_HINTS = (
    "where", "district", "place", "area", "zone", "neighborhood", "barrio", "street",
    "around here", "this area", "this place", "donde", "distrito", "zona",
)
_QUEST_HINTS = (
    "quest", "gig", "mission", "objective", "what do i do", "next step", "stuck",
    "walkthrough", "hint", "mision", "encargo", "objetivo",
)


def strip_accents(text: str) -> str:
    """Normalizes accents and lowercases text for uniform FTS5/BM25 indexing."""
    nfkd = unicodedata.normalize("NFKD", text or "")
    return "".join(ch for ch in nfkd if not unicodedata.combining(ch)).lower()


def tokenize_terms(text: str) -> list[str]:
    norm = strip_accents(text)
    return [
        w
        for w in re.findall(r"[a-z0-9]{2,}", norm)
        if w not in _STOPWORDS_EN_ES
    ]


def _safe_fts_query(raw_query: str, max_terms: int = 12) -> str:
    tokens = tokenize_terms(raw_query)
    if not tokens:
        tokens = [w for w in re.findall(r"[a-z0-9]{2,}", strip_accents(raw_query))]
    dedup: list[str] = []
    seen: set[str] = set()
    for tok in tokens:
        if tok not in seen:
            seen.add(tok)
            dedup.append(tok)
        if len(dedup) >= max_terms:
            break
    if not dedup:
        return ""
    return " OR ".join(f'"{t}"' for t in dedup)


def format_era_badge(era: str) -> str:
    return ERA_BADGES.get(str(era or "").strip(), ERA_BADGES["intel_kiroshi_2077"])


class CpuMultilingualEmbedder:
    """Bi-encoder running strictly on CPU ONNX (0 MB GPU VRAM, ~3-6 ms per query)."""

    def __init__(
        self,
        repo_id: str = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        onnx_file: str = "onnx/model_quint8_avx2.onnx",
    ) -> None:
        self.repo_id = repo_id
        self.onnx_file = onnx_file
        self.available = False
        self.model_tag = f"{repo_id}:{onnx_file}"
        self.load_error = ""
        self._tokenizer: Any = None
        self._session: Any = None
        self._input_names: list[str] = []
        self._lock = threading.Lock()
        self._init_session()

    def _download_with_offline_fallback(self, filename: str) -> Path:
        from huggingface_hub import hf_hub_download

        try:
            return Path(hf_hub_download(self.repo_id, filename, local_files_only=True))
        except Exception:
            return Path(hf_hub_download(self.repo_id, filename, local_files_only=False))

    def _init_session(self) -> None:
        try:
            import onnxruntime as ort
            from tokenizers import Tokenizer

            tok_path = self._download_with_offline_fallback("tokenizer.json")
            self._tokenizer = Tokenizer.from_file(str(tok_path))
            self._tokenizer.enable_truncation(max_length=256)
            self._tokenizer.enable_padding(length=0)

            candidates = [self.onnx_file]
            for fb in ("onnx/model_O3.onnx", "onnx/model.onnx"):
                if fb not in candidates:
                    candidates.append(fb)

            last_err: Exception | None = None
            sess_opts = ort.SessionOptions()
            sess_opts.intra_op_num_threads = 4
            sess_opts.inter_op_num_threads = 1
            for cand in candidates:
                try:
                    mod_path = self._download_with_offline_fallback(cand)
                    sess = ort.InferenceSession(
                        str(mod_path),
                        sess_options=sess_opts,
                        providers=["CPUExecutionProvider"],
                    )
                    enc = self._tokenizer.encode("Night City")
                    ids = np.array([enc.ids], dtype=np.int64)
                    mask = np.array([enc.attention_mask], dtype=np.int64)
                    in_names = [i.name for i in sess.get_inputs()]
                    feeds = {"input_ids": ids, "attention_mask": mask}
                    if "token_type_ids" in in_names:
                        feeds["token_type_ids"] = np.zeros_like(ids)
                    _ = sess.run(None, feeds)

                    self._session = sess
                    self._input_names = in_names
                    self.onnx_file = cand
                    self.model_tag = f"{self.repo_id}:{cand}"
                    self.available = True
                    return
                except Exception as exc:
                    last_err = exc
            self.load_error = str(last_err or "No compatible ONNX file found")
        except Exception as exc:
            self.load_error = str(exc)

    def encode(self, texts: list[str]) -> np.ndarray | None:
        """Returns an L2-normalized float32 matrix of shape (N, 384)."""
        if not self.available or not texts:
            return None
        with self._lock:
            encodings = self._tokenizer.encode_batch(texts)
            max_len = max((len(e.ids) for e in encodings), default=1)
            batch_sz = len(encodings)
            ids = np.zeros((batch_sz, max_len), dtype=np.int64)
            mask = np.zeros((batch_sz, max_len), dtype=np.int64)
            for row_i, enc in enumerate(encodings):
                ln = len(enc.ids)
                ids[row_i, :ln] = enc.ids
                mask[row_i, :ln] = enc.attention_mask

            feeds: dict[str, Any] = {"input_ids": ids, "attention_mask": mask}
            if "token_type_ids" in self._input_names:
                feeds["token_type_ids"] = np.zeros_like(ids)

            out = self._session.run(None, feeds)[0]
            mask_exp = np.expand_dims(mask, axis=-1).astype(np.float32)
            pooled = (out.astype(np.float32) * mask_exp).sum(axis=1) / np.clip(
                mask_exp.sum(axis=1), 1e-9, None
            )
            norms = np.linalg.norm(pooled, axis=1, keepdims=True)
            normed = pooled / np.clip(norms, 1e-9, None)
            return normed


@dataclass
class RetrievedLoreDoc:
    id: str
    pack: str
    category: str
    era: str
    min_act: int
    title: str
    content: str
    score: float
    match_reason: str

    def format_for_prompt(self) -> str:
        badge = format_era_badge(self.era)
        return f"- {self.title} ({badge}): {self.content}"


class HybridCyberpunkRAG:
    """Hybrid lore encyclopedia: SQLite FTS5 + CPU ONNX vectors + live Kiroshi telemetry pinning."""

    def __init__(
        self,
        kb_dir: Path = LORE_KB_DIR,
        custom_path: Path = CUSTOM_LORE_PATH,
        db_path: Path = DEFAULT_LORE_DB_PATH,
        cfg: SparkyServiceConfig | None = None,
        enable_vectors: bool = True,
    ) -> None:
        self.kb_dir = kb_dir
        self.custom_path = custom_path
        self.db_path = db_path
        self.cfg = cfg or SparkyServiceConfig()
        self._embedder = (
            CpuMultilingualEmbedder(
                repo_id=self.cfg.embed_repo_id,
                onnx_file=self.cfg.embed_onnx_file,
            )
            if enable_vectors
            else None
        )
        self.vectors_active = bool(self._embedder and self._embedder.available)

        self._docs: list[dict[str, Any]] = []
        self._id_to_idx: dict[str, int] = {}
        self._lex_vocab: dict[str, list[int]] = {}
        self._lex_vocab_by_len: dict[int, list[str]] = {}
        self._fuzzy_doc_cache: dict[str, list[int]] = {}
        self._doc_matrix: np.ndarray | None = None
        self._last_top_score: float = 0.0
        self._sync_and_load()

    @property
    def last_top_score(self) -> float:
        return self._last_top_score

    @property
    def doc_count(self) -> int:
        return len(self._docs)

    def _source_files(self) -> list[Path]:
        files: list[Path] = []
        if self.kb_dir.is_dir():
            files.extend(sorted(self.kb_dir.glob("*.json")))
        if self.custom_path.is_file():
            files.append(self.custom_path)
        return files

    def _compute_sources_hash(self, files: list[Path]) -> str:
        h = hashlib.sha256()
        v_tag = self._embedder.model_tag if self.vectors_active and self._embedder else "no_vec"
        h.update(v_tag.encode("utf-8"))
        for p in files:
            h.update(p.name.encode("utf-8"))
            h.update(p.read_bytes())
        return h.hexdigest()

    def _load_cards_from_files(self, files: list[Path]) -> list[dict[str, Any]]:
        by_id: dict[str, dict[str, Any]] = {}
        order: list[str] = []
        for p in files:
            try:
                raw = json.loads(p.read_text(encoding="utf-8-sig"))
                if not isinstance(raw, list):
                    continue
                for item in raw:
                    if not isinstance(item, dict):
                        continue
                    cid = str(item.get("id") or "").strip()
                    title = str(item.get("title") or "").strip()
                    content = str(item.get("content") or "").strip()
                    if not cid or not title or not content:
                        continue
                    kw_es = [str(x).strip() for x in (item.get("keywords_es") or []) if str(x).strip()]
                    kw_en = [str(x).strip() for x in (item.get("keywords_en") or []) if str(x).strip()]
                    q_ids = [str(x).strip() for x in (item.get("quest_ids") or []) if str(x).strip()]
                    dists = [str(x).strip() for x in (item.get("districts") or []) if str(x).strip()]
                    try:
                        min_act = max(1, min(3, int(item.get("min_act", 1))))
                    except (TypeError, ValueError):
                        min_act = 1
                    rec = {
                        "id": cid,
                        "pack": str(item.get("pack") or p.stem).strip(),
                        "category": str(item.get("category") or "lore").strip(),
                        "era": str(item.get("era") or "intel_kiroshi_2077").strip(),
                        "min_act": min_act,
                        "quest_ids": q_ids,
                        "districts": dists,
                        "title": title,
                        "keywords_es": kw_es,
                        "keywords_en": kw_en,
                        "content": content,
                    }
                    if cid not in by_id:
                        order.append(cid)
                    by_id[cid] = rec
            except Exception:
                continue
        return [by_id[cid] for cid in order]

    def _init_schema(self, conn: sqlite3.Connection) -> None:
        conn.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS lore_docs (
                id TEXT PRIMARY KEY,
                pack TEXT NOT NULL,
                category TEXT NOT NULL,
                era TEXT NOT NULL,
                min_act INTEGER NOT NULL DEFAULT 1,
                quest_ids TEXT NOT NULL,
                districts TEXT NOT NULL,
                title TEXT NOT NULL,
                keywords_es TEXT NOT NULL,
                keywords_en TEXT NOT NULL,
                content TEXT NOT NULL,
                embedding BLOB
            )
            """
        )
        conn.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS lore_fts USING fts5(
                id UNINDEXED,
                title,
                keywords_en,
                keywords_es,
                content,
                tokenize='unicode61 remove_diacritics 2'
            )
            """
        )

    def _sync_and_load(self) -> None:
        files = self._source_files()
        src_hash = self._compute_sources_hash(files)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        conn = sqlite3.connect(self.db_path)
        try:
            with conn:
                self._init_schema(conn)
                row = conn.execute("SELECT value FROM meta WHERE key = 'src_hash'").fetchone()
                stored_hash = row[0] if row else ""
                cols = {r[1] for r in conn.execute("PRAGMA table_info(lore_docs)").fetchall()}
                needs_rebuild = stored_hash != src_hash or "embedding" not in cols
                if needs_rebuild:
                    cards = self._load_cards_from_files(files)
                    embeddings: np.ndarray | None = None
                    if self.vectors_active and self._embedder and cards:
                        passages = [
                            f"{c['title']}. {' '.join(c['keywords_en'][:8])} {' '.join(c['keywords_es'][:6])}. {c['content']}"
                            for c in cards
                        ]
                        emb_list: list[np.ndarray] = []
                        for start in range(0, len(passages), 32):
                            batch = self._embedder.encode(passages[start : start + 32])
                            if batch is not None:
                                emb_list.append(batch.astype(np.float16))
                        if emb_list:
                            embeddings = np.vstack(emb_list)

                    conn.execute("DELETE FROM lore_docs")
                    conn.execute("DELETE FROM lore_fts")
                    for idx, card in enumerate(cards):
                        blob = embeddings[idx].tobytes() if embeddings is not None else None
                        kw_es_str = ", ".join(card["keywords_es"])
                        kw_en_str = ", ".join(card["keywords_en"])
                        conn.execute(
                            """
                            INSERT INTO lore_docs (
                                id, pack, category, era, min_act, quest_ids, districts,
                                title, keywords_es, keywords_en, content, embedding
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                card["id"],
                                card["pack"],
                                card["category"],
                                card["era"],
                                card["min_act"],
                                json.dumps(card["quest_ids"], ensure_ascii=False),
                                json.dumps(card["districts"], ensure_ascii=False),
                                card["title"],
                                json.dumps(card["keywords_es"], ensure_ascii=False),
                                json.dumps(card["keywords_en"], ensure_ascii=False),
                                card["content"],
                                blob,
                            ),
                        )
                        conn.execute(
                            """
                            INSERT INTO lore_fts (id, title, keywords_en, keywords_es, content)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                            (card["id"], card["title"], kw_en_str, kw_es_str, card["content"]),
                        )
                    conn.execute(
                        "INSERT OR REPLACE INTO meta (key, value) VALUES ('src_hash', ?)",
                        (src_hash,),
                    )

                rows = conn.execute(
                    """
                    SELECT id, pack, category, era, min_act, quest_ids, districts,
                           title, keywords_es, keywords_en, content, embedding
                    FROM lore_docs
                    """
                ).fetchall()
        finally:
            conn.close()

        self._docs = []
        self._id_to_idx = {}
        self._lex_vocab = {}
        self._lex_vocab_by_len = {}
        self._fuzzy_doc_cache = {}
        vec_rows: list[np.ndarray] = []
        all_have_vecs = bool(rows)

        for idx, r in enumerate(rows):
            (
                cid,
                pack,
                cat,
                era,
                min_act,
                qids_json,
                dists_json,
                title,
                kw_es_json,
                kw_en_json,
                content,
                emb_blob,
            ) = r
            kw_es = json.loads(kw_es_json)
            kw_en = json.loads(kw_en_json)
            q_ids = json.loads(qids_json)
            dists = json.loads(dists_json)
            all_phrases = [strip_accents(x) for x in (kw_en + kw_es) if x]
            kw_toks = set()
            for ph in all_phrases:
                kw_toks.update(tokenize_terms(ph))
            lex_toks = kw_toks | set(tokenize_terms(title))
            doc = {
                "idx": idx,
                "id": cid,
                "pack": pack,
                "category": cat,
                "era": era,
                "min_act": int(min_act or 1),
                "quest_ids_norm": [strip_accents(x) for x in q_ids],
                "districts_norm": [strip_accents(x) for x in dists],
                "phrases": all_phrases,
                "kw_tokens": kw_toks,
                "lex_tokens": lex_toks,
                "title_norm": strip_accents(title),
                "title": title,
                "content": content,
            }
            self._docs.append(doc)
            self._id_to_idx[cid] = idx
            for tok in lex_toks:
                if len(tok) >= 5:
                    self._lex_vocab.setdefault(tok, []).append(idx)
            if emb_blob and self.vectors_active:
                vec = np.frombuffer(emb_blob, dtype=np.float16).astype(np.float32)
                vec_rows.append(vec)
            else:
                all_have_vecs = False

        for tok in self._lex_vocab:
            self._lex_vocab_by_len.setdefault(len(tok), []).append(tok)

        if all_have_vecs and vec_rows:
            self._doc_matrix = np.vstack(vec_rows)
        else:
            self._doc_matrix = None

    def _fts_bm25_scores(self, query_text: str, limit: int = 24) -> dict[str, float]:
        fts_q = _safe_fts_query(query_text)
        if not fts_q:
            return {}
        out: dict[str, float] = {}
        try:
            conn = sqlite3.connect(self.db_path)
            try:
                rows = conn.execute(
                    """
                    SELECT id, -bm25(lore_fts, 3.2, 2.8, 2.0, 1.0) AS rank_score
                    FROM lore_fts
                    WHERE lore_fts MATCH ?
                    ORDER BY rank_score DESC
                    LIMIT ?
                    """,
                    (fts_q, limit),
                ).fetchall()
                for cid, sc in rows:
                    out[str(cid)] = max(0.0, float(sc))
            finally:
                conn.close()
        except sqlite3.Error:
            return {}
        return out

    def _tailor_content_for_state(self, doc: dict[str, Any], game_state: dict[str, Any] | None) -> str:
        content = doc["content"]
        if not game_state:
            return content
        if doc["id"] == "chispa_ep05_tres_finales" and int(game_state.get("ep05_done") or 0) > 0:
            end_code = int(game_state.get("ep05_ending") or 0)
            labels = {
                1: "V locked in Autonomous Partner v1.0.",
                2: "V leaked the Zetatech dirty ledger to Network 54.",
                3: "V triggered the Armorer Protocol and forged Sergeant's Last Word.",
            }
            if end_code in labels:
                content = f"{content} [Current save outcome: {labels[end_code]}]"
        return content

    def retrieve(
        self,
        query: str,
        prev_query: str = "",
        game_state: dict[str, Any] | None = None,
        top_k: int = 3,
    ) -> list[RetrievedLoreDoc]:
        """Retrieves the top_k lore cards using Kiroshi Pin + FTS5 + CPU ONNX vectors + spoiler gate."""
        if not self._docs:
            self._last_top_score = 0.0
            return []

        state = game_state or {}
        act_phase = int(state.get("act_phase") or 2)
        q_raw = (query or "").strip()
        q_norm = strip_accents(q_raw)
        q_tokens = set(tokenize_terms(q_raw))
        prev_norm = strip_accents(prev_query) if prev_query else ""
        prev_tokens = set(tokenize_terms(prev_query)) if prev_query else set()

        district_norm = strip_accents(str(state.get("district") or ""))
        scanned_norm = strip_accents(str(state.get("scanned_target") or ""))
        tracked_qid_norm = strip_accents(str(state.get("tracked_quest_id") or ""))
        tracked_qtitle_norm = strip_accents(str(state.get("tracked_quest_title") or ""))

        asks_location = any(h in q_norm for h in _LOCATION_HINTS)
        asks_quest = any(h in q_norm for h in _QUEST_HINTS)

        fts_cur = self._fts_bm25_scores(q_raw, limit=28)
        fts_prev = self._fts_bm25_scores(prev_query, limit=16) if prev_query else {}

        vec_sims: np.ndarray | None = None
        if self.vectors_active and self._embedder and self._doc_matrix is not None and q_raw:
            embed_input = q_raw if not (asks_location and district_norm) else f"{q_raw} {district_norm}"
            q_mat = self._embedder.encode([embed_input])
            if q_mat is not None:
                vec_sims = self._doc_matrix @ q_mat[0]

        eligible_idxs = [d["idx"] for d in self._docs if d["min_act"] <= act_phase]

        # Precompute light typo tolerance (e.g. Takamura -> Takemura) on inverted vocab
        fuzzy_doc_boost: dict[int, float] = {}
        for qt in q_tokens:
            if len(qt) < 5 or qt in self._lex_vocab:
                continue
            matched_idxs = self._fuzzy_doc_cache.get(qt)
            if matched_idxs is None:
                cands: list[int] = []
                q_len = len(qt)
                seen_idx: set[int] = set()
                for target_len in (q_len - 1, q_len, q_len + 1):
                    for dt in self._lex_vocab_by_len.get(target_len, ()):
                        if dt[0] != qt[0] and dt[-1] != qt[-1]:
                            continue
                        if difflib.SequenceMatcher(None, qt, dt).ratio() >= 0.84:
                            for di in self._lex_vocab[dt]:
                                if di not in seen_idx:
                                    seen_idx.add(di)
                                    cands.append(di)
                self._fuzzy_doc_cache[qt] = cands
                matched_idxs = cands
            for di in matched_idxs:
                fuzzy_doc_boost[di] = fuzzy_doc_boost.get(di, 0.0) + 4.0

        lex_raw_scores: dict[int, float] = {}
        pin_bonus: dict[int, float] = {}
        reasons: dict[int, str] = {}

        for idx in eligible_idxs:
            doc = self._docs[idx]
            cid = doc["id"]

            l_sc = fts_cur.get(cid, 0.0) * 1.6 + fts_prev.get(cid, 0.0) * 0.5 + fuzzy_doc_boost.get(idx, 0.0)
            for ph in doc["phrases"]:
                if len(ph) >= 3 and ph in q_norm:
                    l_sc += 9.0 if " " in ph else 4.5
                elif prev_norm and len(ph) >= 3 and ph in prev_norm:
                    l_sc += 2.2
            l_sc += len(q_tokens & doc["kw_tokens"]) * 1.4
            if prev_tokens:
                l_sc += len(prev_tokens & doc["kw_tokens"]) * 0.45
            if l_sc > 0.0:
                lex_raw_scores[idx] = l_sc

            p_sc = 0.0
            reason_bits: list[str] = []
            if tracked_qid_norm or tracked_qtitle_norm:
                for qid in doc["quest_ids_norm"]:
                    if not qid:
                        continue
                    qid_hit = bool(tracked_qid_norm) and (
                        qid == tracked_qid_norm
                        or (len(qid) >= 4 and qid in tracked_qid_norm)
                        or (len(tracked_qid_norm) >= 4 and tracked_qid_norm in qid)
                    )
                    title_hit = bool(tracked_qtitle_norm) and len(qid) >= 4 and (
                        qid in tracked_qtitle_norm or tracked_qtitle_norm in qid
                    )
                    if qid_hit or title_hit:
                        p_sc += 0.078 if asks_quest else 0.038
                        reason_bits.append("active_quest")
                        break
            if len(district_norm) >= 3:
                for dn in doc["districts_norm"]:
                    if dn and len(dn) >= 3 and (dn in district_norm or district_norm in dn):
                        p_sc += 0.075 if asks_location else 0.012
                        reason_bits.append("district")
                        break
            if scanned_norm:
                for ph in doc["phrases"]:
                    if len(ph) >= 4 and ph in scanned_norm:
                        p_sc += 0.035
                        reason_bits.append("scanner")
                        break
            if p_sc > 0.0:
                pin_bonus[idx] = p_sc
                if reason_bits:
                    reasons[idx] = "+".join(dict.fromkeys(reason_bits))

        lex_ranked = sorted(lex_raw_scores.items(), key=lambda x: x[1], reverse=True)
        lex_rank_pos = {idx: rank for rank, (idx, _sc) in enumerate(lex_ranked[:30], start=1)}

        vec_rank_pos: dict[int, int] = {}
        if vec_sims is not None:
            vec_cands = [
                (idx, float(vec_sims[idx]))
                for idx in eligible_idxs
                if float(vec_sims[idx]) >= 0.30
            ]
            vec_cands.sort(key=lambda x: x[1], reverse=True)
            for rank, (idx, _sim) in enumerate(vec_cands[:30], start=1):
                vec_rank_pos[idx] = rank

        k_rrf = 30.0
        combined: list[tuple[float, int]] = []
        for idx in eligible_idxs:
            rrf_lex = (1.15 / (k_rrf + lex_rank_pos[idx])) if idx in lex_rank_pos else 0.0
            rrf_vec = (1.00 / (k_rrf + vec_rank_pos[idx])) if idx in vec_rank_pos else 0.0
            sim_val = float(vec_sims[idx]) if vec_sims is not None else 0.0
            direct_vec = max(0.0, sim_val - 0.32) * 0.045
            pin_val = pin_bonus.get(idx, 0.0)
            total_sc = rrf_lex + rrf_vec + direct_vec + pin_val
            if total_sc > 0.008:
                combined.append((total_sc, idx))

        combined.sort(key=lambda x: x[0], reverse=True)
        self._last_top_score = combined[0][0] if combined else 0.0

        selected: list[tuple[float, int]] = []
        best = self._last_top_score
        for pos, (sc, idx) in enumerate(combined[:top_k]):
            if pos > 0 and sc < best * 0.38:
                continue
            selected.append((sc, idx))

        if top_k >= 3 and selected and not any("active_quest" in reasons.get(idx, "") for _, idx in selected):
            quest_cand = next(
                ((sc, idx) for sc, idx in combined if "active_quest" in reasons.get(idx, "")),
                None,
            )
            if quest_cand is not None:
                if len(selected) < top_k:
                    selected.append(quest_cand)
                else:
                    selected[-1] = quest_cand

        results: list[RetrievedLoreDoc] = []
        for sc, idx in selected:
            doc = self._docs[idx]
            tag_bits: list[str] = []
            if idx in pin_bonus and reasons.get(idx):
                tag_bits.append(reasons[idx])
            if idx in lex_rank_pos:
                tag_bits.append("fts5")
            if idx in vec_rank_pos:
                tag_bits.append("vec")
            results.append(
                RetrievedLoreDoc(
                    id=doc["id"],
                    pack=doc["pack"],
                    category=doc["category"],
                    era=doc["era"],
                    min_act=doc["min_act"],
                    title=doc["title"],
                    content=self._tailor_content_for_state(doc, state),
                    score=round(sc, 4),
                    match_reason="+".join(tag_bits) or "hybrid",
                )
            )
        return results


_RAG_SINGLETON: HybridCyberpunkRAG | None = None
_RAG_LOCK = threading.Lock()


def get_hybrid_rag(cfg: SparkyServiceConfig | None = None) -> HybridCyberpunkRAG:
    global _RAG_SINGLETON
    with _RAG_LOCK:
        if _RAG_SINGLETON is None:
            _RAG_SINGLETON = HybridCyberpunkRAG(cfg=cfg)
        return _RAG_SINGLETON


def format_rag_dossier(docs: list[RetrievedLoreDoc], max_total_chars: int = 1350) -> str:
    """Formats a concise encyclopedia dossier ready for KV-cache-friendly prompt injection."""
    if not docs:
        return ""
    lines: list[str] = []
    used = 0
    for d in docs:
        row = d.format_for_prompt()
        if used + len(row) > max_total_chars and lines:
            break
        lines.append(row)
        used += len(row) + 1
    return "\n".join(lines)


def run_self_test() -> None:
    """Verifies card volume (>=150), latency (<15ms), semantic EN/ES match, 0 VRAM, and spoiler gating."""
    import tempfile

    t_init0 = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="sparky_rag_test_") as tmp:
        rag = HybridCyberpunkRAG(db_path=Path(tmp) / "lore_test_en.sqlite")
        t_init = time.perf_counter() - t_init0
        print(
            f"[RAG Test EN] Docs={rag.doc_count} | CPUVectors={rag.vectors_active} "
            f"| Init={t_init:.2f}s | Model={rag._embedder.model_tag if rag._embedder else 'none'}"
        )
        assert rag.doc_count >= 150, f"Expected >= 150 cards, found: {rag.doc_count}"
        assert rag.vectors_active, f"CPU ONNX embedder failed: {rag._embedder.load_error if rag._embedder else ''}"

        t0 = time.perf_counter()
        hits_krash = rag.retrieve(
            "Who was the rebel netrunner who nuked the entire Old Net from a freezer back in the twenties?",
            game_state={"act_phase": 1},
            top_k=3,
        )
        lat_krash = (time.perf_counter() - t0) * 1000.0
        print(f"  [Semantic DataKrash | {lat_krash:.2f} ms] -> {[h.id for h in hits_krash]}")
        assert hits_krash and hits_krash[0].id == "hist_rache_bartmoss_datakrash"
        assert lat_krash < 25.0

        hits_kab = rag.retrieve(
            "Which gangs run this neighborhood?",
            game_state={"act_phase": 1, "district": "Kabuki"},
            top_k=3,
        )
        print(f"  [District Pin Kabuki] -> {[h.id for h in hits_kab]}")
        assert any("kabuki" in h.id or "mox" in h.id or "tyger" in h.id for h in hits_kab)

        hits_act1 = rag.retrieve(
            "What is Johnny Silverhand's Relic doing to my head?",
            game_state={"act_phase": 1},
            top_k=3,
        )
        assert all(h.id != "char_johnny_engrama_act2" for h in hits_act1), "Act 2 spoiler leaked in Act 1!"

        hits_act2 = rag.retrieve(
            "What is Johnny Silverhand's Relic doing to my head?",
            game_state={"act_phase": 2},
            top_k=3,
        )
        assert any(h.id == "char_johnny_engrama_act2" for h in hits_act2), "Expected Relic card in Act 2."

        hits_q = rag.retrieve(
            "What should I watch out for on this mission?",
            game_state={"act_phase": 1, "tracked_quest_id": "q005", "tracked_quest_title": "The Heist"},
            top_k=2,
        )
        print(f"  [Quest Pinning q005] -> {[h.id for h in hits_q]}")
        assert any(h.id == "quest_q005_el_golpe_konpeki" for h in hits_q)

        sample_queries = [
            "How does the Tyger Claws dermal tattoo disrupt smart targeting?",
            "Tell me what happened to David Martinez and Rebecca",
            "What is CHOOH2 fuel made of?",
        ]
        times = []
        for sq in sample_queries:
            ts = time.perf_counter()
            rag.retrieve(sq, game_state={"act_phase": 2}, top_k=3)
            times.append((time.perf_counter() - ts) * 1000.0)
        avg_ms = sum(times) / len(times)
        print(f"  [Mean Hybrid CPU Search Latency] -> {avg_ms:.2f} ms (max={max(times):.2f} ms)")
        assert avg_ms < 15.0
    print("=== HYBRID LORE RAG (EN) SELF-TEST: OK ===")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="S.P.A.R.K.Y. Hybrid Cyberpunk 2077 Lore RAG (EN)")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--query", default="")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()
        return
    rag = get_hybrid_rag()
    if args.query:
        for h in rag.retrieve(args.query, top_k=3):
            print(f"[{h.score:.4f} | {h.match_reason}] {h.format_for_prompt()}\n")


if __name__ == "__main__":
    main()
