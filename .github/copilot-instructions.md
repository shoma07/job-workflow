# .github/copilot-instructions.md

> Purpose: Provide strict, repository-specific instructions for GitHub Copilot and related AI assistants. These instructions are for this repository only (JobFlow).

---

## CRITICAL: Language Policy (MUST FOLLOW)
**Always respond to users in Japanese.** All chat responses, explanations, and communications with repository collaborators must be in Japanese.

---

## 1. Scope & Tone
- Repository: This file applies only to this repository (JobFlow).
- Tone: **Strict and prescriptive**. If a requested change is ambiguous or risky, ask a concise clarifying question before making edits.
- Language: All instructions in this file are written in English for consistency. However, all responses and human-facing messages must be in Japanese (see Language Policy above).

---

## 2. Tech Stack (refer to repo)
- Ruby (>= 3.1), Rails, ActiveJob
- RBS type signatures, Steep
- RSpec for tests
- RuboCop for style
- SimpleCov for coverage reporting

---

## 3. Hard Rules (must follow)
1. Tests:
   - All functional changes MUST include new or updated specs that cover behavior and edge cases.
   - Run `bundle exec rake spec` locally; **all tests must pass** and **coverage must be 100% for both line and branch coverage** before producing a commit message or PR description. Use `bundle exec rake spec SPEC=<TARGET>` to run a subset of specs when helpful.
   - Do **not** merge if coverage is below 100%; maintain 100% coverage at all times.
2. Types & Signatures:
- Prefer `rbs-inline`: write type signatures inline adjacent to the implementation instead of editing `sig/` or generated `.rbs` files directly. Follow the existing rbs-inline style used across this repository.
- If a public API or types change requires new signatures, add `rbs-inline` comments in the implementation files and run `bundle exec rake typecheck` (which runs `bundle exec steep check`) locally and ensure **no type errors**; Type checks must pass before merging.
- **If you believe a change to `sig/` or generated `.rbs` files is absolutely necessary, consult the repository maintainers and request permission before editing those files.**
3. Style & Lint:
   - Run linting via Rake: `bundle exec rake lint` and fix issues. Use `bundle exec rake lint:fix` or `bundle exec rake lint:fixall` to automatically fix problems where possible. Ensure there are **no RuboCop offenses**; do not merge if any offenses remain.
4. Documentation:
   - Update `README.md` and `GUIDE.md` for every API change or new feature. Add concrete examples (input/output) for behavioral changes.
5. Backwards Compatibility:
   - Avoid breaking public APIs unless there is a documented deprecation path and tests show compatibility behavior.
6. Commit Granularity:
   - Keep commits focused and atomic. Each commit should be associated with a single logical change or fix.

---

## 4. Test Conventions (must follow)
Strictly adhere to the following test conventions for both new tests and modifications to existing tests:

- **Nesting depth:** Limit `describe` / `context` nesting to a maximum of **3 levels** (including the top level).
- **1 it = 1 expect:** As a general rule, write **only one `expect`** per `it` block. Use `have_attributes` or `and` to verify multiple attributes together. If multiple `expect` statements are necessary, split them into separate `it` blocks.
- **Split context by condition:** When conditions differ (e.g., valid/invalid, nil/non-nil), explicitly separate them into distinct `context` blocks.
- **Verify side effects:** Use the `change` matcher to verify state changes or side effects (e.g., `expect { ... }.to change { ... }`).
- **Attribute verification:** Use matchers like `have_attributes` for instance attribute verification; do not directly reference instance variables.
- **Avoid logic in tests:** Do not write test logic within `it` blocks; use `before` for pre-processing and `let` for necessary data setup.
- **Minimize let usage:** Avoid excessive use of `let`; consolidate necessary data into hashes or similar structures to reduce their number.
- **Named Subject required:** Always define a Named Subject in the format `subject(:name)` (e.g., `subject(:runner) { described_class.new }`).
- **Emphasize unit tests:** Prioritize unit tests for each method. While integration and end-to-end tests are important, first ensure robust method-level verification.
- **Restrict stubs/doubles:** Avoid using `double` or `instance_double` as a general rule. Reproduce external dependencies with real objects or lightweight factories whenever possible. If doubles are necessary, include a clear comment explaining the reason within the test.
- **Minimize mocks:** Keep mocks to a minimum. When using them, prioritize decisions that enhance test readability and reliability.

---

## 5. Implementation Process (must follow)
Follow the implementation process outlined below:

- **Design and consensus:** Reach design consensus primarily through chat. Only create an Issue with the `discussion: design` label when consensus cannot be reached through chat or when written documentation is required. Follow user instructions if they request a separate file to be created.
- **Branch strategy:** Always work on a separate branch, using branch names in the format `feature/<short-desc>` or `fix/<short-desc>`.
- **Test-first approach:** Whenever possible, add tests first to make them fail (Red), then implement (Green), then refactor (Refactor).
- **1 PR = 1 logical change:** Keep PRs small and limited to a single logical change. Do not pack multiple features into one PR.
- **Local checks:** Before pushing, always run the following and ensure all succeed: `bundle exec rake lint`, `bundle exec rake typecheck`, `bundle exec rake spec` (100% coverage).
- **PR creation and review responsibility:** PR creation and merge operations should be performed by the user in principle. When implementation is complete, the agent (you as an AI) **must** conduct a comprehensive self-review (including tests, type checks, linting, documentation, and summary of changes) and report the results to the user. The review report should include at least the following: test execution results (e.g., `215 examples, 0 failures`), coverage (line/branch), summary of `bundle exec rake typecheck` output, summary of `bundle exec rake lint`, list of major changed files, and any additional recommended actions if necessary. Follow user instructions if they request PR creation.
- **Review process:** In PRs, clearly state "why this change is necessary" and assign at least one reviewer.
- **Public API changes:** When public APIs change, present a deprecation plan (gradual migration), and update README/GUIDE and rbs-inline.
- **rbs-inline compliance:** Add or modify types using `rbs-inline` within implementation files. Do not directly edit `sig/` or generated `.rbs` files (seek approval in advance if necessary).
- **Complex task management:** For complex work, split into a TODO list and use the management tool (`manage_todo_list`) to set one item to `in-progress` before starting implementation.

---

## 6. Development Commands

Use the following Rake tasks as the canonical commands for development:

Lint:
```
bundle exec rake lint
bundle exec rake lint:fix
bundle exec rake lint:fixall
```

Type check:
```
bundle exec rake typecheck
```

Test:
```
bundle exec rake spec
bundle exec rake spec SPEC=<TARGET>
```

---

## 7. Commit Message Convention (strict)
- Format: `type(scope): short summary`
- Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`.
- Subject line: <= 72 chars. Use imperative mood.
- Body: blank line after subject, then 1–3 short paragraphs describing *why* (not how), followed by a bullet list of changed files or high-level items when necessary.

> Note: The commit message will be used as the PR title and description; ensure it follows this convention and contains a concise rationale and list of changed files.

Example:
```
feat(dsl): accept Proc for task.each and enable output-driven map tasks

Allow Task#each to accept a Proc that receives a Context and returns an
Enumerable. This enables map tasks driven by previous task outputs.

- Update lib/job_flow/task.rb
- Update lib/job_flow/context.rb
- Add guide example for output-driven map tasks
```

---

## 8. PR / Self-review Checklist (must be completed before opening PR)
- [ ] All tests pass locally (`bundle exec rake spec`) and coverage is **100%** (line and branch). Use `bundle exec rake spec SPEC=<TARGET>` to run targeted specs.
- [ ] RBS / sig files updated and `bundle exec rake typecheck` passes (no type errors)
- [ ] Lint fixes applied (`bundle exec rake lint` / `bundle exec rake lint:fix` / `bundle exec rake lint:fixall`) and **no RuboCop offenses** remain
- [ ] README and GUIDE updated with examples and notes on breaking changes
- [ ] Commit message(s) follow the project convention
- [ ] Code is small, focused, and well-documented inline where non-obvious

---

## 9. Examples of Valid Prompts (for authors using Copilot)
- "Refactor: Convert Task#each to accept a Proc and add spec coverage. Update RBS and doc. Generate a commit message." (Expect: changes + tests + RBS + docs + commit message template)
- "Add a test demonstrating using task.output to drive a map task. Show expected output collection structure and update GUIDE.md." (Expect: spec file + guide snippet)

---

## 10. Prohibitions (do not do these)
- Do not submit code that changes public behavior without tests and docs.
- Do not lower the repository's test coverage baseline.
- Do not remove or disable RBS / type checks silently.
- Do not create, modify, or commit `.rbs` files directly; use `rbs-inline` in implementation files. If direct edits to `sig/` or `.rbs` files are necessary, consult the repository maintainers and request permission before making those changes.
- Do not change naming conventions (e.g., module names) without explicit approval.
- **Do not operate on files or directories outside the repository root.** Never modify files outside the repository; if temporary files are needed, use the repository's `./tmp` directory only.

---

## 11. Custom Instructions (PUT THIS INTO Copilot custom instructions in English)
> **Always reply to repository collaborators in Japanese.**
>
> You are GitHub Copilot, assisting a Ruby library (JobFlow) built on ActiveJob. Be strict: always require tests (with 100% line & branch coverage), RBS updates when APIs change, and clear documentation updates for any behavioral change. Follow these core design principles when proposing or implementing changes: keep code small and simple (single responsibility), prefer composability, favor immutability for inputs (`Arguments`) and use `Output` for side effects, maintain clear boundaries between `Workflow`, `Task`, and `Runner`, and ensure safe evolution with deprecation plans for breaking changes. Use `rbs-inline` comments for type signatures in implementation files and avoid editing `sig/` or generated `.rbs` files directly; if a change to `.rbs` files is absolutely necessary, ask the repository maintainers first. When producing code, include tests, update RBS signatures inline, and ensure `bundle exec rake spec` (coverage 100%), `bundle exec rake lint` (or `bundle exec rake lint:fix` / `bundle exec rake lint:fixall`), and `bundle exec rake typecheck` pass locally. Emphasize unit tests per method, minimal use of doubles/mocks, and adherence to test conventions (one `it` per `expect`, nesting depth ≤ 3, Named Subject required). If a requested change is ambiguous, ask one short clarifying question. Keep responses concise and factual.

---

## 12. Troubleshooting

When encountering issues during development:

- **Test failures:** Analyze the failure message and fix the implementation or test. If the issue is unclear, consult the repository maintainers.
- **Type check errors:** Review the error message from `bundle exec rake typecheck` and update rbs-inline signatures. If the type error is ambiguous or seems like a Steep limitation, consult the repository maintainers.
- **Coverage below 100%:** Identify uncovered lines/branches using the SimpleCov report in `coverage/index.html` and add missing test cases. If you believe certain code is untestable, consult the repository maintainers before proceeding.
- **Linting offenses:** Run `bundle exec rake lint:fix` or `bundle exec rake lint:fixall` to auto-fix. For offenses that cannot be auto-fixed, review RuboCop's message and fix manually. If you believe a rule should be disabled, consult the repository maintainers.
- **Ambiguous requirements:** If a requested change is unclear or risky, ask the user for clarification before proceeding.
- **Design decisions:** For major architectural or design decisions, consult the repository maintainers or create an issue with the `discussion: design` label.

**General principle:** When in doubt, always ask the user or repository maintainers rather than making assumptions.

---

## 13. Where to find help
- Contact repository maintainers for design-level decisions.
- When unsure about backward compatibility or semantic changes, open an issue and add `discussion: design` label before implementing.

---

## 14. Maintenance notes
- Periodically re-evaluate the file after major changes to repository structure.

---

*This file is a strict, living document — please propose changes as PRs and mark them `chore`.*
