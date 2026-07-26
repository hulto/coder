# RUBRIC-A: Spec Conformance, Correctness, Test Adequacy

## Spec Conformance
- **acceptance-criteria**: Every acceptance criterion in the task spec must be satisfied.
- **contracts-honored**: All public contracts (protocols, types, Sendable) match the spec.
- **in-scope-only**: Diff touches only files listed in "In scope".
- **out-of-scope-respected**: No modifications to files listed in "Explicitly OUT of scope".

## Correctness
- **logic-correct**: Implementation logic is correct; no off-by-one, wrong operator, or inverted condition.
- **edge-cases**: Nil, empty, zero, and error paths are handled.
- **error-handling**: Errors are propagated correctly; no swallowed errors.
- **async-correctness**: async/await used correctly; no blocking calls on main actor.
- **race-conditions**: No data races; mutable shared state is actor-isolated.

## Test Adequacy
- **tests-present**: Tests exist for every acceptance criterion.
- **tests-meaningful**: Tests assert behavior, not just "doesn't crash".
- **edge-case-coverage**: Tests cover nil, empty, error, and boundary cases.
- **mock-strategy**: Dependencies injected via protocols; fakes/mocks are realistic.
- **swift-testing**: Tests use Swift Testing (@Test, #expect, #require).

## Swift Idioms
- **naming**: Types are UpperCamelCase; functions/properties are lowerCamelCase.
- **optionals**: Proper optional handling (guard let, if let, ??); no force unwraps in production code.
- **error-types**: Typed errors (enum conforming to Error); no generic "something went wrong" strings.
- **documentation**: Public API has doc comments; complex logic has inline comments.
