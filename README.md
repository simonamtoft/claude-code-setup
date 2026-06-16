# Claude Code

My personal preferences for working with Claude Code as a consultant across many projects, each with different codebases, programming languages, infrastructure, etc.

## Skills to add
- techdebt; end-of-sessions weep for duplicated and dead code
- grill; adversarial code review
- worktree; create git worktree for parallel Claude sessions
- review-changes; review uncomitted changes and suggest improvements
- quick-commit; stage all changes and commit with a descriptive message

## Sub-agents to add
- code-simplifier; simplify code after Claude is done working
- code-architect; design reviews and architectural decisions
- verify-app; thoroughly test the application works correctly
- build validator; ensure project builds correctly for deployment
- staff-reviewer; review plans and architectures as a skeptical staff engineer

## Post hooks
- "Stop" if test don't pass; return text that says keep going

Also something to ensure documentation is updated.

When a command finishes running with !, Claude should start again.