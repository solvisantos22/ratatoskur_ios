# Ratatoskur iOS App

Ratatoskur is an AI math coach for handwritten student work. The iOS app gives students a notebook-style workspace where they can upload a math problem, write a solution with Apple Pencil, and receive mode-specific feedback in Icelandic.

This repository contains the active iOS product prototype for Ratatoskur.

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

CLI build example:

```bash
xcodebuild -project ratatoskur.xcodeproj -scheme ratatoskur -destination 'generic/platform=iOS' build
```

## Notes and Limitations

- Math rendering uses MathJax from CDN (`jsdelivr`), so tutor math formatting requires network access.
- Autosave is best-effort; write failures are intentionally non-blocking.
- The app is still a product prototype and should be tested carefully before use with real student data.
