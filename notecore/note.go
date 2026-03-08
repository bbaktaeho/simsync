// Package notecore provides the shared business logic for SimSync note management.
// It is used by both the desktop (Wails) and mobile (Flutter + Go via gomobile bind) clients.
package notecore

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Note represents a single markdown note tied to a date.
type Note struct {
	ID        string `json:"id"`
	NoteDate  string `json:"note_date"`  // "2026-03-08"
	Title     string `json:"title"`
	Content   string `json:"content"`
	IsDefault bool   `json:"is_default"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

// NoteMeta represents note metadata for list views.
type NoteMeta struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	IsDefault bool   `json:"is_default"`
	UpdatedAt string `json:"updated_at"`
}

// NoteStore handles note persistence using the local filesystem.
// Notes are stored as markdown files with YAML frontmatter, organized by date.
type NoteStore struct {
	dataDir string
}

// NewNoteStore creates a NoteStore with the given data directory.
func NewNoteStore(dataDir string) (*NoteStore, error) {
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("creating data directory: %w", err)
	}
	return &NoteStore{dataDir: dataDir}, nil
}

// DefaultDataDir returns the default data directory path (~/.simsync/documents).
func DefaultDataDir() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("getting home directory: %w", err)
	}
	return filepath.Join(homeDir, ".simsync", "documents"), nil
}

// SaveNote saves a note to disk. If id is empty, a new note is created.
// The isDefault flag is automatically determined if this is the first note for the date.
func (s *NoteStore) SaveNote(noteDate, id, title, content string) (*Note, error) {
	if err := validateDate(noteDate); err != nil {
		return nil, err
	}

	dateDir := filepath.Join(s.dataDir, noteDate)
	if err := os.MkdirAll(dateDir, 0755); err != nil {
		return nil, fmt.Errorf("creating date directory: %w", err)
	}

	now := time.Now().Format(time.RFC3339)
	isNew := id == ""

	if isNew {
		id = fmt.Sprintf("%d", time.Now().UnixNano())
	}

	filePath := filepath.Join(dateDir, id+".md")

	// Determine isDefault and createdAt
	isDefault := false
	createdAt := now

	if isNew {
		// First note for this date becomes the default
		existing, _ := s.ListNotesByDate(noteDate)
		isDefault = len(existing) == 0
	} else {
		// Preserve existing metadata
		if existing, err := s.LoadNote(noteDate, id); err == nil {
			isDefault = existing.IsDefault
			createdAt = existing.CreatedAt
		}
	}

	data := formatFrontmatter(title, noteDate, isDefault, createdAt, now) + content
	if err := os.WriteFile(filePath, []byte(data), 0644); err != nil {
		return nil, fmt.Errorf("writing note %s: %w", id, err)
	}

	return &Note{
		ID:        id,
		NoteDate:  noteDate,
		Title:     title,
		Content:   content,
		IsDefault: isDefault,
		CreatedAt: createdAt,
		UpdatedAt: now,
	}, nil
}

// LoadNote reads a note from disk.
func (s *NoteStore) LoadNote(noteDate, id string) (*Note, error) {
	filePath := filepath.Join(s.dataDir, noteDate, id+".md")
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("reading note %s/%s: %w", noteDate, id, err)
	}
	return parseNote(id, string(data)), nil
}

// ListNotesByDate returns metadata for all notes on a given date, sorted by creation time.
func (s *NoteStore) ListNotesByDate(noteDate string) ([]NoteMeta, error) {
	dateDir := filepath.Join(s.dataDir, noteDate)
	entries, err := os.ReadDir(dateDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("listing notes for %s: %w", noteDate, err)
	}

	notes := make([]NoteMeta, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
			continue
		}
		id := strings.TrimSuffix(entry.Name(), ".md")
		data, err := os.ReadFile(filepath.Join(dateDir, entry.Name()))
		if err != nil {
			continue
		}
		note := parseNote(id, string(data))
		notes = append(notes, NoteMeta{
			ID:        note.ID,
			Title:     note.Title,
			IsDefault: note.IsDefault,
			UpdatedAt: note.UpdatedAt,
		})
	}

	// Default note first, then by creation order (ID is timestamp-based)
	sort.Slice(notes, func(i, j int) bool {
		if notes[i].IsDefault != notes[j].IsDefault {
			return notes[i].IsDefault
		}
		return notes[i].ID < notes[j].ID
	})

	return notes, nil
}

// DeleteNote removes a note from disk.
func (s *NoteStore) DeleteNote(noteDate, id string) error {
	filePath := filepath.Join(s.dataDir, noteDate, id+".md")
	if err := os.Remove(filePath); err != nil {
		return fmt.Errorf("deleting note %s/%s: %w", noteDate, id, err)
	}

	// Clean up empty date directory
	dateDir := filepath.Join(s.dataDir, noteDate)
	entries, err := os.ReadDir(dateDir)
	if err == nil && len(entries) == 0 {
		os.Remove(dateDir)
	}

	return nil
}

// GetMonthNotes returns a list of dates (as "YYYY-MM-DD" strings) in the given
// year/month that have at least one note.
func (s *NoteStore) GetMonthNotes(year, month int) ([]string, error) {
	entries, err := os.ReadDir(s.dataDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("reading data directory: %w", err)
	}

	prefix := fmt.Sprintf("%04d-%02d-", year, month)
	var dates []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasPrefix(name, prefix) {
			continue
		}
		// Verify directory has at least one .md file
		dateEntries, err := os.ReadDir(filepath.Join(s.dataDir, name))
		if err != nil {
			continue
		}
		for _, de := range dateEntries {
			if !de.IsDir() && strings.HasSuffix(de.Name(), ".md") {
				dates = append(dates, name)
				break
			}
		}
	}

	sort.Strings(dates)
	return dates, nil
}

func validateDate(noteDate string) error {
	if _, err := time.Parse("2006-01-02", noteDate); err != nil {
		return fmt.Errorf("invalid date format %q (expected YYYY-MM-DD): %w", noteDate, err)
	}
	return nil
}

func formatFrontmatter(title, noteDate string, isDefault bool, createdAt, updatedAt string) string {
	return fmt.Sprintf("---\ntitle: %s\nnote_date: %s\nis_default: %v\ncreated_at: %s\nupdated_at: %s\n---\n",
		title, noteDate, isDefault, createdAt, updatedAt)
}

func parseNote(id, raw string) *Note {
	note := &Note{ID: id, Title: "Untitled"}

	if !strings.HasPrefix(raw, "---\n") {
		note.Content = raw
		return note
	}

	end := strings.Index(raw[4:], "\n---\n")
	if end == -1 {
		note.Content = raw
		return note
	}

	frontmatter := raw[4 : 4+end]
	note.Content = raw[4+end+5:]

	for _, line := range strings.Split(frontmatter, "\n") {
		key, val, ok := strings.Cut(line, ": ")
		if !ok {
			continue
		}
		switch key {
		case "title":
			note.Title = val
		case "note_date":
			note.NoteDate = val
		case "is_default":
			note.IsDefault = val == "true"
		case "created_at":
			note.CreatedAt = val
		case "updated_at":
			note.UpdatedAt = val
		}
	}

	if note.Title == "" {
		note.Title = "Untitled"
	}

	return note
}
