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
- **Compliance:** All instructions in this document are MANDATORY. Deviations are not permitted without explicit user approval.

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
- **Test through public APIs only:** NEVER use `instance_variable_set`, `instance_variable_get`, or any reflection methods to manipulate or inspect object state in tests. Always interact with objects through their public interface. If you need to set up specific internal state, provide proper factory methods, test helpers, or builder patterns. This ensures tests remain maintainable and coupled to the public contract, not internal implementation details.
- **Avoid logic in tests:** Do not write test logic within `it` blocks; use `before` for pre-processing and `let` for necessary data setup.
- **Minimize let usage:** Avoid excessive use of `let`; consolidate necessary data into hashes or similar structures to reduce their number.
- **Handling RSpec/MultipleMemoizedHelpers violations:** When a test context exceeds the `let` limit (default 5), apply ONE of the following strategies:
  
  **Strategy 1 - Hash-based configuration (preferred for related parameters):**
  ```ruby
  let(:base_config) { { param1: default1, param2: default2, param3: default3 } }
  let(:config) { base_config }  # Override in nested contexts
  
  context "when param1 is special" do
    let(:config) { base_config.merge(param1: special_value) }
  end
  ```
  
  **Strategy 2 - Inline let definitions (preferred for independent setup per context):**
  Move `let` definitions from the parent scope into each `context` block. This reduces the `let` count in the parent scope while keeping test setup clear and localized.
  ```ruby
  context "when condition A" do
    let(:param1) { value_a }
    let(:param2) { value_a2 }
    # ... test using param1, param2
  end
  
  context "when condition B" do
    let(:param1) { value_b }
    let(:param2) { value_b2 }
    # ... test using param1, param2
  end
  ```
  
  Choose the strategy that maintains the best readability for the specific test case. Only apply these patterns when RuboCop reports `RSpec/MultipleMemoizedHelpers` violations; do not use them preemptively.
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
- **Local checks:** Before pushing, always run the following Rake commands and ensure all succeed:
  - `bundle exec rake spec` (NOT `bundle exec rspec`) - must achieve 100% line and branch coverage
  - `bundle exec rake lint` (use `lint:fix` or `lint:fixall` for auto-fixes)
  - `bundle exec rake typecheck`
  
  **CRITICAL: Never use `bundle exec rspec` directly. Always use `bundle exec rake spec`.**
- **PR creation and review responsibility:** PR creation and merge operations should be performed by the user in principle. When implementation is complete, the agent (you as an AI) **must** conduct a comprehensive self-review (including tests, type checks, linting, documentation, and summary of changes) and report the results to the user. The review report should include at least the following: test execution results (e.g., `215 examples, 0 failures`), coverage (line/branch), summary of `bundle exec rake typecheck` output, summary of `bundle exec rake lint`, list of major changed files, and any additional recommended actions if necessary. Follow user instructions if they request PR creation.
- **Review process:** In PRs, clearly state "why this change is necessary" and assign at least one reviewer.
- **Public API changes:** When public APIs change, present a deprecation plan (gradual migration), and update README/GUIDE and rbs-inline.
- **rbs-inline compliance:** Add or modify types using `rbs-inline` within implementation files. Do not directly edit `sig/` or generated `.rbs` files (seek approval in advance if necessary).
- **Complex task management:** For complex work, split into a TODO list and use the management tool (`manage_todo_list`) to set one item to `in-progress` before starting implementation.

---

## 6. Development Commands (MANDATORY)

**ALWAYS use these Rake tasks. Do NOT use raw commands like `bundle exec rspec` directly.**

Lint:
```bash
bundle exec rake lint           # Check for style violations
bundle exec rake lint:fix       # Auto-fix safe violations
bundle exec rake lint:fixall    # Auto-fix all possible violations
```

Type check:
```bash
bundle exec rake typecheck      # Run Steep type checker
```

Test:
```bash
bundle exec rake spec                    # Run all tests
bundle exec rake spec SPEC=<TARGET>      # Run specific test file or directory
# Example: bundle exec rake spec SPEC=spec/job_flow/context_spec.rb
# Example: bundle exec rake spec SPEC=spec/job_flow/context_spec.rb:42
```

**Why use Rake tasks:**
- They ensure consistent environment setup
- They may include additional validations or setup steps
- They are the officially supported interface for this repository
- Direct use of `bundle exec rspec` bypasses project-specific configuration

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
- **Do not use `instance_variable_set`, `instance_variable_get`, or similar reflection methods in tests.** Always test through public APIs only. If you need to set internal state for testing, provide proper public methods or test helpers. Using reflection to access private state is an anti-pattern that creates brittle tests and violates encapsulation.

---

## 11. Custom Instructions (PUT THIS INTO Copilot custom instructions in English)
> **Always reply to repository collaborators in Japanese.**
>
> You are GitHub Copilot, assisting a Ruby library (JobFlow) built on ActiveJob. Be strict: always require tests (with 100% line & branch coverage), RBS updates when APIs change, and clear documentation updates for any behavioral change. Follow these core design principles when proposing or implementing changes: keep code small and simple (single responsibility), prefer composability, favor immutability for inputs (`Arguments`) and use `Output` for side effects, maintain clear boundaries between `Workflow`, `Task`, and `Runner`, and ensure safe evolution with deprecation plans for breaking changes. Use `rbs-inline` comments for type signatures in implementation files and avoid editing `sig/` or generated `.rbs` files directly; if a change to `.rbs` files is absolutely necessary, ask the repository maintainers first. When producing code, include tests, update RBS signatures inline, and ALWAYS run `bundle exec rake spec` (NOT `bundle exec rspec`), `bundle exec rake lint`, and `bundle exec rake typecheck` - these Rake commands are MANDATORY. Tests must achieve 100% coverage, use only public APIs (NEVER use `instance_variable_set` or `instance_variable_get`), follow test conventions (one `it` per `expect`, nesting depth ≤ 3, Named Subject required), and minimize `let` usage (use Hash-based configuration when RSpec/MultipleMemoizedHelpers violations occur). Emphasize unit tests per method and minimal use of doubles/mocks. If a requested change is ambiguous, ask one short clarifying question. Keep responses concise and factual.

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
