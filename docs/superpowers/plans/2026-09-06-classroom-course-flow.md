# Classroom Course Flow Implementation Plan

> **For agentic workers:** Use subagent-driven-development for bounded model/backend tasks, then review and verify the complete flow.

**Goal:** Present Mínir bekkir → class home → assignment set → exercise, preserving Ratatoskur's theme and saved work.

**Architecture:** Keep the existing backend classroom relationships. Drive the detail NavigationStack with typed assignment/exercise routes owned by StudentClassroomModel. Selecting a class clears the detail path and invalidates pending exercise opens. Use AppTheme.Auth colours for all class surfaces, existing logo and serif headings; retain the existing notebook.

**Tech stack:** SwiftUI/Observation/PencilKit and the existing FastAPI class response.

## Accepted scope

- Start with an overview of joined classes instead of silently selecting the first class.
- Each class has a named home showing the teacher's display name when available and cards for its assignment sets.
- An assignment screen lists its exercises; opening an exercise retains the existing persistent notebook and teacher policy.
- Selecting any class, including the current one, returns to that class's home. A delayed response from a previous location cannot reopen an old exercise.
- Sidebar remains accessible; compact layouts use the same hierarchy with native back navigation.
- Preserve cream/brown AppTheme surfaces, logo, serif headings, readable body text and existing notebook appearance. Use no new palette.
- Student-facing class metadata adds nullable teacher_name from the owner's full_name, never a fallback email. Existing clients and older backend responses remain compatible.

## Work and verification

- [x] Model: add StudentClassroomRoute; tests reproduce stale exercise open when class selection changes and when leaving an assignment. Implement path invalidation and keep selection on refresh without automatically choosing a class.
- [x] Backend: add nullable teacher_name in ClassResponse and populate the owner display name. Add meaningful response/ownership coverage and run backend suite.
- [x] UI: replace flat exercise lists with themed class overview, class home and assignment detail views. Style sidebar and join form with existing AppTheme; rename the entry point Mínir bekkir. Keep notebook construction and draft saving intact.
- [x] Verify full iOS tests and simulator build; visually inspect overview, class home, assignment, notebook, class switching and compact navigation. Check handwriting retention and missing-teacher compatibility.
- [x] Review spec and code quality, fix concrete findings, update usage notes.

## Verification recorded on 2026-09-06

- 39 iOS unit tests passed, including 13 classroom navigation/recovery tests; Debug and Release simulator builds succeeded.
- 58 backend tests passed; teacher portal lint passed.
- iPad simulator: inspected the overview, teacher display, class home, assignment cards, notebook context, sidebar reopening and join sheet. Switching to another class and selecting the current class both return to the correct home. All seven existing test pen strokes remained after leaving and reopening the original notebook.
- iPhone simulator: inspected the compact overview and assignment screens; opened an exercise and returned through the assignment to the class home. The existing notebook's drawing toolbar remains cramped at phone widths; its layout is outside this course-navigation change.
- Legacy/missing teacher names are covered by iOS decoding and backend response tests. No email fallback is exposed.
- Spec review passed. Code review found a swallowed class-refresh error after joining; fixed it and verified failure followed by successful retry.

Repository handoff: pull incoming work, push the checked milestone to main in both repositories, and confirm local and remote main match.

No new grading, messaging, scheduling or course-administration features are included. Live AI and physical iPad testing still await the key and device.
