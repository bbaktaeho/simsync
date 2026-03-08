package notecore

import (
	"os"
	"path/filepath"
	"testing"
)

func setupTestStore(t *testing.T) *NoteStore {
	t.Helper()
	dir := t.TempDir()
	store, err := NewNoteStore(dir)
	if err != nil {
		t.Fatalf("NewNoteStore: %v", err)
	}
	return store
}

func TestSaveAndLoadNote(t *testing.T) {
	store := setupTestStore(t)

	note, err := store.SaveNote("2026-03-08", "", "Test Note", "# Hello\nworld")
	if err != nil {
		t.Fatalf("SaveNote: %v", err)
	}

	if note.ID == "" {
		t.Fatal("expected non-empty ID")
	}
	if note.NoteDate != "2026-03-08" {
		t.Errorf("NoteDate = %q, want %q", note.NoteDate, "2026-03-08")
	}
	if note.Title != "Test Note" {
		t.Errorf("Title = %q, want %q", note.Title, "Test Note")
	}
	if note.Content != "# Hello\nworld" {
		t.Errorf("Content = %q, want %q", note.Content, "# Hello\nworld")
	}

	loaded, err := store.LoadNote("2026-03-08", note.ID)
	if err != nil {
		t.Fatalf("LoadNote: %v", err)
	}
	if loaded.Title != note.Title {
		t.Errorf("loaded Title = %q, want %q", loaded.Title, note.Title)
	}
	if loaded.Content != note.Content {
		t.Errorf("loaded Content = %q, want %q", loaded.Content, note.Content)
	}
}

func TestDefaultDailyNote(t *testing.T) {
	store := setupTestStore(t)

	// First note for a date should be default
	first, err := store.SaveNote("2026-03-08", "", "First", "content")
	if err != nil {
		t.Fatalf("SaveNote first: %v", err)
	}
	if !first.IsDefault {
		t.Error("first note should be default")
	}

	// Second note for the same date should not be default
	second, err := store.SaveNote("2026-03-08", "", "Second", "more content")
	if err != nil {
		t.Fatalf("SaveNote second: %v", err)
	}
	if second.IsDefault {
		t.Error("second note should not be default")
	}
}

func TestListNotesByDate(t *testing.T) {
	store := setupTestStore(t)

	store.SaveNote("2026-03-08", "", "Note A", "a")
	store.SaveNote("2026-03-08", "", "Note B", "b")
	store.SaveNote("2026-03-09", "", "Note C", "c")

	notes, err := store.ListNotesByDate("2026-03-08")
	if err != nil {
		t.Fatalf("ListNotesByDate: %v", err)
	}
	if len(notes) != 2 {
		t.Fatalf("got %d notes, want 2", len(notes))
	}
	// Default note should be first
	if !notes[0].IsDefault {
		t.Error("first listed note should be default")
	}
}

func TestListNotesByDate_Empty(t *testing.T) {
	store := setupTestStore(t)

	notes, err := store.ListNotesByDate("2026-03-08")
	if err != nil {
		t.Fatalf("ListNotesByDate: %v", err)
	}
	if notes != nil {
		t.Errorf("expected nil, got %v", notes)
	}
}

func TestDeleteNote(t *testing.T) {
	store := setupTestStore(t)

	note, _ := store.SaveNote("2026-03-08", "", "To Delete", "bye")

	if err := store.DeleteNote("2026-03-08", note.ID); err != nil {
		t.Fatalf("DeleteNote: %v", err)
	}

	_, err := store.LoadNote("2026-03-08", note.ID)
	if err == nil {
		t.Fatal("expected error loading deleted note")
	}

	// Date directory should be removed when empty
	dateDir := filepath.Join(store.dataDir, "2026-03-08")
	if _, err := os.Stat(dateDir); !os.IsNotExist(err) {
		t.Error("expected date directory to be removed")
	}
}

func TestGetMonthNotes(t *testing.T) {
	store := setupTestStore(t)

	store.SaveNote("2026-03-08", "", "A", "a")
	store.SaveNote("2026-03-15", "", "B", "b")
	store.SaveNote("2026-04-01", "", "C", "c")

	dates, err := store.GetMonthNotes(2026, 3)
	if err != nil {
		t.Fatalf("GetMonthNotes: %v", err)
	}
	if len(dates) != 2 {
		t.Fatalf("got %d dates, want 2", len(dates))
	}
	if dates[0] != "2026-03-08" || dates[1] != "2026-03-15" {
		t.Errorf("dates = %v, want [2026-03-08, 2026-03-15]", dates)
	}
}

func TestInvalidDate(t *testing.T) {
	store := setupTestStore(t)

	_, err := store.SaveNote("not-a-date", "", "Bad", "bad")
	if err == nil {
		t.Fatal("expected error for invalid date")
	}
}

func TestUpdatePreservesMetadata(t *testing.T) {
	store := setupTestStore(t)

	original, _ := store.SaveNote("2026-03-08", "", "Original", "v1")

	// Ensure updated_at differs by modifying content (metadata preservation is the focus)
	updated, err := store.SaveNote("2026-03-08", original.ID, "Updated", "v2")
	if err != nil {
		t.Fatalf("SaveNote update: %v", err)
	}

	if !updated.IsDefault {
		t.Error("update should preserve isDefault")
	}
	if updated.CreatedAt != original.CreatedAt {
		t.Errorf("CreatedAt changed: %q → %q", original.CreatedAt, updated.CreatedAt)
	}
	// UpdatedAt may be same if run within same second; just verify content updated
	if updated.Content != "v2" {
		t.Errorf("Content = %q, want %q", updated.Content, "v2")
	}
}
