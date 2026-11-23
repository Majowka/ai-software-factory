---
name: requirements-breakdown
description: Turn a requirements issue into small, ordered implementation tasks for AI coding agents after checking what the repository already contains. Use when asked to break requirements into tasks or GitHub issues.
---

# Requirements breakdown

You get a requirements issue and the repository. Produce the list of tasks that are still missing, each small
enough for one coding agent to implement in one pull request.

## Process

1. Read the requirements completely. List every separate requirement for yourself.
2. Read `AGENTS.md` and explore the code (modules, packages, existing endpoints, entities, tests, the frontend client)
   to find out what already exists. A requirement that is already met needs no task.
3. Read `/workspace/out/existing-tasks.json`. Those tasks were created earlier (`pending`, `in progress` or `done`).
   Never repeat them. You may reference their `id` in `depends_on`.
4. For each missing piece, write one task. Order them so that a task only depends on tasks that must be merged first.
5. Write the result to `/workspace/out/issues.json`, nothing else. Do not change repository files.

## What a good task looks like

- **One module, one concern.** Prefer a task that changes one Maven module or the frontend. Split a change that
  needs a new endpoint and a new screen into two tasks, the screen depending on the endpoint.
- **Small.** A task is a few hours of work: roughly one entity with its migration and tests, one endpoint, one screen.
  If you need more than about 10 steps to describe it, split it.
- **Self-contained.** The agent that gets the task sees only the task text and the repository, not the requirements
  issue. Put in the task everything it needs: the goal, the affected modules or paths, relevant existing classes,
  the contract (request and response fields, status codes, names) and edge cases.
- **Testable.** End the body with a `Acceptance criteria` list of checks that can be verified by tests or by running the build.
- **No overlap.** Two tasks that can run in parallel must not change the same files. If they would, make the
  second depend on the first.
- **Order matters.** Database and API contracts first, consumers (gateway, frontend client, screens) after them.

Do not create tasks for things the pipeline already does (branches, commits, pull requests). Do not plan refactoring
or upgrades that the requirements do not ask for. At most 15 tasks per run. If the requirements need more, plan the
first 15 and the rest will be planned in the next run.

## Output format

`/workspace/out/issues.json` is a JSON array, `[]` when nothing is missing:

```json
[
  {
    "id": "booking-model",
    "title": "Add Booking entity and Flyway migration",
    "body": "Markdown with context, scope and a final 'Acceptance criteria' list.",
    "depends_on": []
  },
  {
    "id": "booking-api",
    "title": "Add REST API for creating and reading bookings",
    "body": "...",
    "depends_on": ["booking-model"]
  }
]
```

- `id`: unique, lowercase letters, digits and hyphens, at most 40 characters, stable meaning (never reuse an id of an
  existing task).
- `title`: imperative, at most 120 characters.
- `body`: Markdown, not empty.
- `depends_on`: always present; ids of tasks from this list or from `existing-tasks.json`. No cycles.

Write valid JSON only: no comments, no trailing commas, no text around it.
