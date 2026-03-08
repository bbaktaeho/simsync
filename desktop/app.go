package main

import (
	"context"
	"fmt"
	"os"

	"simsync/notecore"
)

// App is the main application struct bound to the Wails frontend.
// ctx is stored here as required by the Wails lifecycle (startup callback).
type App struct {
	ctx   context.Context
	store *notecore.NoteStore
}

// NewApp creates a new App and initializes the note store.
func NewApp() *App {
	dataDir, err := notecore.DefaultDataDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to get data directory: %v\n", err)
		dataDir = ".simsync-data"
	}

	store, err := notecore.NewNoteStore(dataDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create note store: %v\n", err)
	}

	return &App{store: store}
}

// startup is called by Wails when the app starts.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// Login is a stub authentication. Always succeeds if email and password are non-empty.
func (a *App) Login(email, password string) *notecore.AuthResult {
	return notecore.Login(email, password)
}

// SaveNote saves a note for the given date. If id is empty, a new note is created.
func (a *App) SaveNote(noteDate, id, title, content string) (*notecore.Note, error) {
	return a.store.SaveNote(noteDate, id, title, content)
}

// LoadNote reads a note by date and ID.
func (a *App) LoadNote(noteDate, id string) (*notecore.Note, error) {
	return a.store.LoadNote(noteDate, id)
}

// ListNotesByDate returns all notes for a given date.
func (a *App) ListNotesByDate(noteDate string) ([]notecore.NoteMeta, error) {
	return a.store.ListNotesByDate(noteDate)
}

// DeleteNote removes a note by date and ID.
func (a *App) DeleteNote(noteDate, id string) error {
	return a.store.DeleteNote(noteDate, id)
}

// GetMonthNotes returns dates with notes for a given year/month.
func (a *App) GetMonthNotes(year, month int) ([]string, error) {
	return a.store.GetMonthNotes(year, month)
}
