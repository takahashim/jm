-- jm initial schema (SPEC 18). Applied only by `jm init` / `jm migrate`.

-- Core item table. The public id "JM-000042" is derived from id (SPEC 5.2).
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'inbox',
  priority INTEGER NOT NULL DEFAULT 0,
  resolution TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  archived_at TEXT
);

CREATE INDEX idx_items_state ON items (state);
CREATE INDEX idx_items_priority ON items (priority);
CREATE INDEX idx_items_updated_at ON items (updated_at);

-- Time-ordered records attached to an item (SPEC 7).
CREATE TABLE entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  kind TEXT NOT NULL DEFAULT 'comment',
  body TEXT NOT NULL,
  created_by TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

CREATE INDEX idx_entries_item ON entries (item_id, created_at);

-- Prior title/body kept when an item's title or body changes (SPEC 17).
CREATE TABLE item_revisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

CREATE INDEX idx_item_revisions_item ON item_revisions (item_id, created_at);

-- Source repositories associated with items (SPEC 8).
CREATE TABLE repositories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  path TEXT,
  remote_url TEXT,
  default_branch TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Item <-> repository association (relation-less, SPEC 8.3).
CREATE TABLE item_repositories (
  item_id INTEGER NOT NULL,
  repository_id INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (item_id, repository_id),
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);

-- Directed item relations, stored in normalized form (SPEC 9).
CREATE TABLE item_relations (
  source_item_id INTEGER NOT NULL,
  target_item_id INTEGER NOT NULL,
  relation TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (source_item_id, target_item_id, relation),
  FOREIGN KEY (source_item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (target_item_id) REFERENCES items(id) ON DELETE CASCADE,
  CHECK (source_item_id != target_item_id)
);

-- External references (SPEC 10). Table name avoids the reserved word.
CREATE TABLE item_references (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  repository_id INTEGER,
  kind TEXT NOT NULL,
  value TEXT NOT NULL,
  label TEXT,
  metadata_json TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (repository_id) REFERENCES repositories(id) ON DELETE SET NULL
);

-- Idempotency for `jm ref add` (SPEC 14.1.2). NULL repository_id is folded to
-- a fixed value so distinct references are unique but re-adds are no-ops.
CREATE UNIQUE INDEX idx_item_references_unique
  ON item_references (item_id, kind, value, COALESCE(repository_id, -1));

CREATE INDEX idx_item_references_item ON item_references (item_id);

-- Free-form tags, case-insensitive unique, first-writer casing (SPEC 11).
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE COLLATE NOCASE
);

CREATE TABLE item_tags (
  item_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (item_id, tag_id),
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- Mutable process state as key-value (SPEC 18.12).
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
);

-- Full-text search over title/body/entry only, trigram tokenizer (SPEC 19).
CREATE VIRTUAL TABLE items_fts USING fts5(
  title, body,
  content='items', content_rowid='id',
  tokenize='trigram'
);

CREATE VIRTUAL TABLE entries_fts USING fts5(
  body,
  content='entries', content_rowid='id',
  tokenize='trigram'
);

-- External-content sync triggers. UPDATE deletes the old row image then
-- inserts the new one so non-indexed column changes stay consistent (SPEC 19.1).
CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
  INSERT INTO items_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
END;
CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, title, body)
    VALUES ('delete', old.id, old.title, old.body);
END;
CREATE TRIGGER items_au AFTER UPDATE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, title, body)
    VALUES ('delete', old.id, old.title, old.body);
  INSERT INTO items_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
END;

CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
  INSERT INTO entries_fts(rowid, body) VALUES (new.id, new.body);
END;
CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
  INSERT INTO entries_fts(entries_fts, rowid, body) VALUES ('delete', old.id, old.body);
END;
CREATE TRIGGER entries_au AFTER UPDATE ON entries BEGIN
  INSERT INTO entries_fts(entries_fts, rowid, body) VALUES ('delete', old.id, old.body);
  INSERT INTO entries_fts(rowid, body) VALUES (new.id, new.body);
END;
