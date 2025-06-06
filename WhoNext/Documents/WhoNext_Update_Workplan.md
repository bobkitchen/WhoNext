
# 🛠️ WhoNext Update: UX + Logic Improvements

## ✅ Objective
Implement three key improvements to WhoNext’s user experience and logic handling across the Insights and People views.

---

## 1. Fix Conversation Logging Logic in Suggestions
**Current Problem:**  
Clicking ❌ next to a person in the Insights suggestion list is interpreted as a logged conversation, affecting stats and last-contact tracking.

**Fix:**  
- Modify the `onDismiss` action to:
  - Only hide the person from the suggestion list (e.g. with a `.dismissedToday = true` flag if needed).
  - Do *not* update `lastContactDate`, `conversationCount`, or include them in insights logic.
- Stats and smart suggestions must be driven *exclusively* by actual logged `Conversation` records.

---

## 2. Make Pre-Meeting Prompt User Customizable
**Current Problem:**  
The prompt used in `Generate Pre-Meeting Brief` is hardcoded.

**Fix:**  
- Add a `@AppStorage` `String` property (e.g. `customPreMeetingPrompt`) in `SettingsView`.
- Add a labeled multiline `TextField` for user to edit this prompt.
- Update the button in `PersonDetailView` to reference the saved string from `AppStorage`.

---

## 3. Render Markdown in Conversation Views
**Current Problem:**  
Markdown-formatted notes are shown as raw text (e.g. `##`, `*`).

**Fix:**  
- Use `Text(.init(conversation.notes))` instead of `Text(conversation.notes)` in all views where Markdown should render.
- Ensure the preview list, detail window, and any static previews show rendered Markdown.
- Optional: allow editing in raw Markdown but preview as rendered.

---

## Additional Notes
- App is already set up with iCloud sync; migration risk should be managed carefully if any Core Data model changes are needed.
- No schema updates are currently required for these changes.
