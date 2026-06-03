# iOS App Architecture

## Overview

The Ratatoskur iOS app is a SwiftUI and PencilKit notebook for AI-assisted math tutoring. It lets students upload a problem image, write a handwritten solution, and submit the work to the backend for mode-specific feedback.

## Main Areas

- `Core/API`: endpoint definitions, multipart upload, API client, transport error mapping.
- `Core/Auth`: access-token handling, refresh/session bootstrap, keychain storage.
- `Core/Models`: API request/response models and app-level errors.
- `Core/Storage`: local notebook draft persistence.
- `Features/Auth`: login and registration.
- `Features/Problems`: problem list, folders, and exam prep entry points.
- `Features/Notebook`: problem image, PencilKit canvas, pages, query submission, reading confirmation, response cards, and attempt history.
- `Shared`: theme, reusable UI, SVG/logo and math rendering helpers.

## Product UX Principles

- Preserve student work after AI request failure.
- Make AI uncertainty visible through reading-confirmation flows.
- Avoid forcing redraw/re-upload when retrying.
- Keep tutoring modes explicit so students can choose how much help they want.
- Treat long latency as a user-trust issue, not just a networking issue.
