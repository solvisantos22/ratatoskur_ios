# UX Testing Notes

## Reading Confirmation Flow

Use this checklist to validate the unclear-handwriting confirmation flow in Debug builds.

### Setup

1. Build and run the app in `Debug`.
2. Open any notebook problem.
3. In the action panel, tap the debug unclear-reading control if available.

### Text Input

1. Keep one unclear item in text mode.
2. Tap inside the text field.
3. Insert math symbols such as `x^2`, `^`, `/`, `(`, `)`.
4. Verify the entry remains editable and symbols append correctly.

### Drawing Correction

1. Switch one unclear item to drawing mode.
2. Write a correction.
3. Toggle eraser modes.
4. Clear and redraw.
5. Submit.

Expected result:

- Drawing canvas remains smooth.
- Eraser mode selection is reflected.
- Submission proceeds when at least one valid correction is present.

### Mixed Submission

1. Use text mode for one item and drawing mode for another.
2. Leave one item empty intentionally.
3. Submit.

Expected result:

- If all entries are empty, an inline error appears.
- With at least one valid correction, submission proceeds.
- Sheet closes and notebook continues to evaluation flow.

### Context Hints

Confirm that unclear blocks show region hints and confidence values when provided by the backend.
