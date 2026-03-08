import './style.css';
import { marked } from 'marked';
import { Login, SaveNote, LoadNote, ListNotesByDate, DeleteNote, GetMonthNotes } from '../wailsjs/go/main/App';

// --- Types ---
interface NoteMeta {
  id: string;
  title: string;
  is_default: boolean;
  updated_at: string;
}

// --- State ---
let currentNoteId = '';
let currentNoteDate = '';
let currentYear = 0;
let currentMonth = 0;
let autoSaveTimer: ReturnType<typeof setTimeout> | null = null;
let monthNoteDates: Set<string> = new Set();
let calendarExpanded = true;

const app = document.querySelector('#app')!;

// --- Screens ---
function showLogin() {
  app.innerHTML = `
    <div class="login-screen">
      <div class="login-box">
        <h1>SimSync</h1>
        <p class="login-subtitle">Simple Sync — Personal Note System</p>
        <form id="login-form">
          <input id="login-email" type="email" placeholder="Email" required />
          <input id="login-password" type="password" placeholder="Password" required />
          <button type="submit" class="btn-login">Login</button>
        </form>
        <div id="login-error" class="login-error"></div>
      </div>
    </div>
  `;

  document.getElementById('login-form')!.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = (document.getElementById('login-email') as HTMLInputElement).value;
    const password = (document.getElementById('login-password') as HTMLInputElement).value;
    const errorEl = document.getElementById('login-error')!;

    try {
      const result = await Login(email, password);
      if (result.success) {
        showMain();
      } else {
        errorEl.textContent = result.message;
      }
    } catch (err) {
      errorEl.textContent = 'Login failed';
    }
  });
}

function showMain() {
  const today = new Date();
  currentYear = today.getFullYear();
  currentMonth = today.getMonth() + 1;
  const todayStr = formatDate(today);

  app.innerHTML = `
    <div class="layout">
      <aside class="sidebar">
        <div class="sidebar-header">
          <h2>SimSync</h2>
          <button id="btn-logout" class="btn-logout" title="Logout">Logout</button>
        </div>
        <div class="calendar-section">
          <div class="calendar-nav">
            <button id="cal-prev" class="cal-nav-btn">&lt;</button>
            <span id="cal-title" class="cal-title"></span>
            <button id="cal-next" class="cal-nav-btn">&gt;</button>
            <button id="cal-toggle" class="cal-nav-btn cal-toggle-btn" title="Toggle calendar">&#9650;</button>
          </div>
          <div id="cal-body" class="calendar-body">
            <div class="calendar-grid">
              <div class="cal-header">Mo</div><div class="cal-header">Tu</div><div class="cal-header">We</div>
              <div class="cal-header">Th</div><div class="cal-header">Fr</div><div class="cal-header">Sa</div>
              <div class="cal-header">Su</div>
            </div>
            <div id="cal-days" class="calendar-days"></div>
          </div>
        </div>
        <div class="notes-section">
          <div class="notes-header">
            <span id="notes-date-label">Notes</span>
            <button id="btn-new-note" class="btn-new" title="New note">+</button>
          </div>
          <div id="note-list" class="note-list"></div>
        </div>
      </aside>
      <main class="editor-area">
        <div class="editor-header">
          <input id="note-title" type="text" placeholder="Note title..." />
        </div>
        <div class="editor-body">
          <div class="pane edit-pane">
            <textarea id="editor" placeholder="Write your markdown here..."></textarea>
          </div>
          <div class="pane preview-pane">
            <div id="preview" class="markdown-body"></div>
          </div>
        </div>
        <div class="editor-footer">
          <span id="status"></span>
        </div>
      </main>
    </div>
  `;

  // Element references
  const editorEl = document.getElementById('editor') as HTMLTextAreaElement;
  const previewEl = document.getElementById('preview')!;
  const titleEl = document.getElementById('note-title') as HTMLInputElement;
  const noteListEl = document.getElementById('note-list')!;
  const statusEl = document.getElementById('status')!;

  marked.setOptions({ breaks: true, gfm: true });

  // --- Event listeners ---
  document.getElementById('btn-logout')!.addEventListener('click', () => {
    currentNoteId = '';
    currentNoteDate = '';
    showLogin();
  });

  document.getElementById('cal-prev')!.addEventListener('click', () => {
    currentMonth--;
    if (currentMonth < 1) { currentMonth = 12; currentYear--; }
    renderCalendar();
  });

  document.getElementById('cal-next')!.addEventListener('click', () => {
    currentMonth++;
    if (currentMonth > 12) { currentMonth = 1; currentYear++; }
    renderCalendar();
  });

  document.getElementById('cal-toggle')!.addEventListener('click', () => {
    calendarExpanded = !calendarExpanded;
    const calBody = document.getElementById('cal-body')!;
    const toggleBtn = document.getElementById('cal-toggle')!;
    calBody.classList.toggle('collapsed', !calendarExpanded);
    toggleBtn.innerHTML = calendarExpanded ? '&#9650;' : '&#9660;';
  });

  document.getElementById('btn-new-note')!.addEventListener('click', () => {
    if (!currentNoteDate) {
      currentNoteDate = todayStr;
    }
    createNewNote();
  });

  editorEl.addEventListener('input', () => {
    renderPreview();
    scheduleAutoSave();
  });

  titleEl.addEventListener('input', () => {
    scheduleAutoSave();
  });

  // --- Functions ---
  function renderPreview() {
    const html = marked.parse(editorEl.value);
    if (typeof html === 'string') {
      previewEl.innerHTML = html;
    }
  }

  function scheduleAutoSave() {
    if (autoSaveTimer) clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(() => saveCurrentNote(), 1000);
  }

  async function saveCurrentNote() {
    if (!currentNoteDate) return;

    const title = titleEl.value.trim() || 'Untitled';
    const content = editorEl.value;

    try {
      const note = await SaveNote(currentNoteDate, currentNoteId, title, content);
      currentNoteId = note.id;
      statusEl.textContent = `Saved at ${new Date().toLocaleTimeString()}`;
      refreshNoteList();
      refreshCalendarDots();
    } catch (err) {
      statusEl.textContent = 'Save failed';
      console.error(err);
    }
  }

  async function loadNote(noteDate: string, id: string) {
    try {
      const note = await LoadNote(noteDate, id);
      currentNoteId = note.id;
      currentNoteDate = note.note_date;
      titleEl.value = note.title;
      editorEl.value = note.content;
      renderPreview();
      statusEl.textContent = '';
      highlightActiveNote();
    } catch (err) {
      console.error(err);
    }
  }

  async function deleteNote(noteDate: string, id: string) {
    try {
      await DeleteNote(noteDate, id);
      if (currentNoteId === id) {
        currentNoteId = '';
        titleEl.value = '';
        editorEl.value = '';
        previewEl.innerHTML = '';
        statusEl.textContent = '';
      }
      refreshNoteList();
      refreshCalendarDots();
    } catch (err) {
      console.error(err);
    }
  }

  async function refreshNoteList() {
    if (!currentNoteDate) {
      noteListEl.innerHTML = '';
      return;
    }

    try {
      const notes: NoteMeta[] = await ListNotesByDate(currentNoteDate) || [];
      const label = document.getElementById('notes-date-label')!;
      label.textContent = `Notes — ${currentNoteDate}`;
      noteListEl.innerHTML = '';

      for (const note of notes) {
        const item = document.createElement('div');
        item.className = `note-item${note.id === currentNoteId ? ' active' : ''}`;
        item.dataset.id = note.id;

        const indicator = document.createElement('span');
        indicator.className = 'note-default-dot';
        indicator.textContent = note.is_default ? '●' : ' ';

        const titleSpan = document.createElement('span');
        titleSpan.className = 'note-item-title';
        titleSpan.textContent = note.title || 'Untitled';
        titleSpan.addEventListener('click', () => loadNote(currentNoteDate, note.id));

        const deleteBtn = document.createElement('button');
        deleteBtn.className = 'note-item-delete';
        deleteBtn.textContent = '×';
        deleteBtn.title = 'Delete';
        deleteBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          deleteNote(currentNoteDate, note.id);
        });

        item.appendChild(indicator);
        item.appendChild(titleSpan);
        item.appendChild(deleteBtn);
        noteListEl.appendChild(item);
      }
    } catch (err) {
      console.error(err);
    }
  }

  function highlightActiveNote() {
    noteListEl.querySelectorAll('.note-item').forEach((el) => {
      const item = el as HTMLElement;
      item.classList.toggle('active', item.dataset.id === currentNoteId);
    });
  }

  function createNewNote() {
    currentNoteId = '';
    titleEl.value = '';
    editorEl.value = '';
    previewEl.innerHTML = '';
    statusEl.textContent = '';
    editorEl.focus();
  }

  async function refreshCalendarDots() {
    try {
      const dates: string[] = await GetMonthNotes(currentYear, currentMonth) || [];
      monthNoteDates = new Set(dates);
    } catch {
      monthNoteDates = new Set();
    }
  }

  async function renderCalendar() {
    await refreshCalendarDots();

    const calTitle = document.getElementById('cal-title')!;
    const calDays = document.getElementById('cal-days')!;

    const monthNames = ['January','February','March','April','May','June',
      'July','August','September','October','November','December'];
    calTitle.textContent = `${monthNames[currentMonth - 1]} ${currentYear}`;

    // First day of month (0=Sun, adjust to Mon=0)
    const firstDay = new Date(currentYear, currentMonth - 1, 1).getDay();
    const startOffset = (firstDay + 6) % 7; // Monday-based
    const daysInMonth = new Date(currentYear, currentMonth, 0).getDate();

    calDays.innerHTML = '';

    // Empty cells before first day
    for (let i = 0; i < startOffset; i++) {
      const empty = document.createElement('div');
      empty.className = 'cal-day empty';
      calDays.appendChild(empty);
    }

    // Day cells
    for (let d = 1; d <= daysInMonth; d++) {
      const dateStr = `${currentYear}-${String(currentMonth).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      const cell = document.createElement('div');
      cell.className = 'cal-day';

      if (dateStr === todayStr) cell.classList.add('today');
      if (dateStr === currentNoteDate) cell.classList.add('selected');
      if (monthNoteDates.has(dateStr)) cell.classList.add('has-notes');

      cell.innerHTML = `<span class="cal-day-num">${d}</span>${monthNoteDates.has(dateStr) ? '<span class="cal-dot"></span>' : ''}`;

      cell.addEventListener('click', () => {
        currentNoteDate = dateStr;
        currentNoteId = '';
        titleEl.value = '';
        editorEl.value = '';
        previewEl.innerHTML = '';
        statusEl.textContent = '';
        refreshNoteList();
        // Update selected state
        calDays.querySelectorAll('.cal-day').forEach(c => c.classList.remove('selected'));
        cell.classList.add('selected');
      });

      calDays.appendChild(cell);
    }
  }

  async function selectDate(dateStr: string) {
    currentNoteDate = dateStr;
    await refreshNoteList();
    renderCalendar();
  }

  // --- Init ---
  renderCalendar();
  selectDate(todayStr);
}

// --- Helpers ---
function formatDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// --- Start ---
showLogin();
