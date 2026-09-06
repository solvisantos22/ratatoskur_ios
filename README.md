# Ratatoskur iOS App

Ratatoskur is an AI math coach for handwritten student work. The iOS app gives students a notebook-style workspace where they can upload a math problem, write a solution with Apple Pencil, and receive mode-specific feedback in Icelandic.

This repository contains the active iOS product prototype for Ratatoskur.

## Shared Development Workflow

Sölvi and Jóhannes work in these repositories together. Fetch both repositories
before starting work, pull incoming changes on the active branch, and check for
updates again before pushing. If a shared branch has diverged, merge its incoming
commits and check the combined result; do not force-push or rewrite teammates'
history. Bring relevant updates from `main` into feature branches as work proceeds.

Commit and push small, checked milestones regularly, including at the end of a
work session. Pull incoming `main` changes, merge each checked milestone into
`main`, and push it so teammates receive the current work. Keep outstanding
Xcode/device checks explicit. Coordinate API changes across both
repositories. Keep product decisions and meeting materials in Notion.

## Product Experience

Students can:

- Sign in or register.
- Create and manage problems.
- Upload a problem image from camera or photo library.
- Write a multi-page solution using PencilKit.
- Submit in different tutoring modes: `Hint`, `Check Step`, `Reveal`.
- Confirm unclear handwriting when the AI is uncertain.
- Retry or cancel long AI requests without losing their drawing.
- Review tutor responses and past attempts.

## Tech Stack

- Swift + SwiftUI
- PencilKit for handwriting canvas
- `URLSession` for API communication
- `WKWebView` + MathJax for rendering math in tutor responses
- Keychain for access-token storage
- Local draft persistence in Application Support

## App Flow

1. `MathCoachApp` boots and calls `AuthManager.bootstrap()`.
2. If authenticated, user sees `ProblemsOverviewView`.
3. User opens or creates a problem and enters `NotebookView`.
4. User uploads a problem image and writes a solution on canvas.
5. Frontend submits a multipart request to backend `/query`.
6. Tutor response, reading-confirmation state, and attempts list are shown in the notebook.

## Main Features

- Auth: login/register/logout with session bootstrap + refresh.
- Explicit registration consent toggles for analytics and dataset use.
- Problem list + create new problem.
- Notebook workspace with problem image picker.
- PencilKit canvas with zoom.
- Adjustable writing area height.
- Fullscreen writing mode.
- Mode picker: `Hint`, `Check Step`, `Reveal`.
- AI reading-confirmation flow for unclear handwriting.
- Retry/cancel UX for long-running AI submissions.
- Attempt history sheet with optional solution image URL.
- Autosave drafts: drawing, image, mode, expert mode.

## Project Structure

```text
MathCoach/
  MathCoachApp.swift          # app entry + root routing
  Core/
    API/                      # API client, endpoints, multipart builder
    Auth/                     # auth/session management + keychain
    Models/                   # request/response + app errors
    Storage/                  # local draft persistence
  Features/
    Auth/                     # login/register UI
    Problems/                 # overview list + create flow
    Notebook/                 # workspace, canvas, query submission
  Shared/                     # reusable UI components
```

## API Contract Examples

The frontend and backend live in separate repositories, so response-shape drift is a real risk. JSON contract examples live in `api_contract_examples/` and are covered by Swift decoding tests.

The query contract currently covers:

- `hint`
- `check_solution`
- `reveal`
- `confirm_reading`
- `ask_clarification`

## Configuration

Base backend URL is read from Info.plist key:

- `BACKEND_BASE_URL`

Development fallback default if key is missing:

- `http://127.0.0.1:8000/`

Implementation reference: `MathCoach/Core/Config.swift`.

### Frontend Config Example

You can define the backend URL in an `.xcconfig` file and map it into Info.plist:

```xcconfig
BACKEND_BASE_URL = https://your-backend.example.com/
```

Info.plist entry:

```xml
<key>BACKEND_BASE_URL</key>
<string>$(BACKEND_BASE_URL)</string>
```

## Backend Endpoints Used

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `GET /auth/me`
- `POST /auth/logout`
- `POST /query` multipart
- `GET /problems`
- `POST /problem`
- `GET /problems/{problemId}/attempts`

Implementation reference: `MathCoach/Core/API/Endpoint.swift`.

## Running Locally

1. Open `ratatoskur.xcodeproj` in Xcode.
2. Select scheme `ratatoskur`.
3. Set `BACKEND_BASE_URL` in target Info settings if needed.
4. Build and run on simulator/device.

In the iPad simulator, click and drag with the mouse or trackpad to write on the
canvas. Simulator builds accept touch input for walkthroughs without an Apple
Pencil. Physical devices retain Pencil-only drawing. Open **Mínir bekkir** to
join a class and try an assigned exercise; the local backend must be running.

CLI build example:

```bash
xcodebuild -project ratatoskur.xcodeproj -scheme ratatoskur -destination 'generic/platform=iOS' build
```

## Notes and Limitations

- Teachers can disable full worked solutions on assigned exercises. Hints and
  checks remain available. The notebook applies the current assignment policy
  when opening and when returning to the app; the backend also checks every
  request. A saved disabled Reveal selection becomes Hint while keeping its ink.
  The existing correct-attempt requirement for Reveal still applies when allowed.

- Math rendering uses MathJax from CDN (`jsdelivr`), so tutor math formatting requires network access.
- Autosave is best-effort; write failures are intentionally non-blocking.
- The app is still a product prototype and should be tested carefully before use with real student data.

## Classroom assignments

Open **Mínir bekkir** on the overview and choose **Ganga í bekk**. Enter the code supplied by the teacher. The flow is **Mínir bekkir → class home → assignment set → exercise → notebook**. The class home shows its teacher when that name is available and cards for its assignment sets; opening a set lists the exercises. Selecting a class in the sidebar always returns to that class's home, including when another notebook was open. Pending opens from the old location are ignored. **Bekkir** restores the sidebar and **Verkefnasett** returns from the notebook to its exercise list. The class, assignment and join screens reuse the existing cream/brown AppTheme, logo and serif headings. The existing SwiftUI/PencilKit notebook opens with the teacher's original image. Sending a hint/check/reveal request uses the ordinary `/query` flow and links that attempt to the teacher's assignment.

- The teacher can see submitted handwriting, attempts and tutor feedback for assigned exercises. Unsaved/in-progress local ink is not automatically sent to the teacher. Personal notebooks are excluded from the teacher dashboard.
- Reopening always calls the idempotent assignment start endpoint to obtain the existing problem ID and a fresh signed image URL. Saved local pages and handwriting are restored by that ID; attempt history is loaded normally.
- Assigned images cannot be replaced, including when an assigned notebook is opened through the ordinary problem list. Image loading must succeed before submitting an assigned exercise; retrying refreshes the signed URL. The backend also enforces the original exercise image.
- Signed image downloads use a separate session without backend bearer credentials or cookies.
- Local handwriting drafts stay on the device. Opening the same account on another device retrieves attempt history, not an editable copy of its local PencilKit draft.

Classroom endpoints: `GET /student/classes`, `POST /student/classes/join`, `GET /student/assignments`, and `POST /student/assignments/{assignment_id}/items/{item_id}/start`.

## Local demo on a physical iPad

1. Run the backend so it listens on the computer's network interface (`0.0.0.0`, not just `127.0.0.1`). Configure its signed storage/public URLs so they are reachable from the iPad too.
2. Connect the computer and iPad to the same Wi-Fi network. Find the computer's local IP address in System Settings → Wi-Fi → Details → TCP/IP.
3. In Xcode, select your own development team under Signing & Capabilities, connect/select the iPad, enable Developer Mode if prompted, and run the **Debug** configuration. Device signing must be completed by the developer who owns the Apple account.
4. Before logging in, tap **Tengistillingar** and enter e.g. `http://192.168.1.20:8000/` using the computer's actual address. Save, allow Local Network access if prompted, and sign in. To change servers later, sign out first. Changing the address clears stored bearer credentials, cookies and the old network session.
5. Join a class using its code, open an assignment and write with Apple Pencil. Submit a hint/check and verify that the teacher browser shows the actual submitted image and feedback. Close/reopen the notebook to check the local draft.

The simulator default remains `http://127.0.0.1:8000/`. The app remembers a manually selected address. **Nota sjálfgefna tengingu** restores the configured default. Debug builds declare local network access and use `NSAllowsLocalNetworking`; Release builds add no ATS exception and the address editor requires HTTPS. See [Apple's local networking ATS documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Simulator tests cover classroom response decoding, request routes, backend credential isolation, and restoring real serialized PencilKit strokes with an assigned image. A temporary iOS-client integration test also passed against a disposable local backend: login, join, class/assignment listing, repeated start with a stable problem ID, signed image download, ordinary-list assignment markers, empty attempt history, and local ink restoration. It did not request AI feedback. Unsigned simulator tests use an in-memory token store because Keychain persistence is unavailable without signing; production continues to use KeychainStore.

Physical iPad connectivity, Apple Pencil interaction, visual/multitasking checks and the complete live teacher/student submission flow still require the device check above.


### Draft isolation when changing servers or accounts

New local drafts are stored separately for each normalized backend base URL (including its API path), authenticated user ID and problem ID. Open notebooks and delayed autosaves keep the scope captured when the notebook was opened. Export and local deletion use that same server/account scope.

Legacy files in `Application Support/ProblemDrafts/<problem-id>/` contain no trustworthy server or owner metadata. They are preserved in place and are never automatically adopted, uploaded, moved or deleted by the new scoped storage. If such a draft exists for an opened problem, the app explains that it is still on the device but cannot be identified safely. Recovery requires identifying its original server/account and explicitly copying its pages into the correct scoped notebook; this prototype does not yet offer an in-app recovery tool. Keep a backup of the app container before any manual recovery.
