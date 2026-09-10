# Choosing a language for herdr plugins

Choose the language deliberately for each plugin. Python is not the default.
Use the simplest maintainable implementation that meets the plugin's operating
requirements; Rust's build and distribution costs need a concrete benefit.

## Start with the workload

Identify how the plugin runs: an occasional user action, a frequent event hook,
or a continuously running background process. Determine whether its time is
spent on its own computation, starting processes, waiting on external tools or
the network, or sleeping. Consider invocation frequency, latency, CPU usage,
resident memory, and concurrent work.

| Workload | Language guidance |
| --- | --- |
| A few straightforward commands with little parsing or state | Use shell when quoting and error handling remain simple. |
| Occasional orchestration of `git`, `gh`, `herdr`, or network requests | Favor a small script. Choose Python deliberately when structured data, branching, or cleanup would make shell fragile and an interpreter is acceptable. |
| Continuously active background loops, high-frequency hooks, sustained parsing or computation | Prefer Rust when execution cost, repeated startup, memory use, or responsiveness matters at the expected frequency. |
| A background process that mostly sleeps or waits on tools or I/O | Evaluate its actual CPU, memory, and latency needs; running in the background alone does not justify Rust. |

For example, a watcher continuously processing events can benefit from Rust.
A user-invoked PR-worktree action that coordinates several Git and GitHub
commands is a good fit for a small script when those external operations
dominate the wait. Frequent invocations can make small per-call costs material,
so evaluate their cumulative cost.

## Weigh the whole implementation

- Account for code complexity, structured data handling, testing, and maintenance.
  Avoid turning shell into a large application merely to avoid an interpreter.
- Account for installation on supported platforms: interpreter availability and
  dependencies for scripts; Cargo/toolchain requirements or maintaining prebuilt
  binaries for Rust. A Rust port that still invokes external tools still needs
  those tools.
- Types, concurrency support, existing libraries, and shared code can justify
  Rust when they simplify the actual implementation. Consistency with another
  plugin's language is a secondary consideration.
- Keep the design efficient in any language. Prefer events or fewer subprocess
  calls where appropriate before trying to fix needless polling or expensive
  external operations with a language change.

## Verify the deciding assumption

When a performance claim would change the choice and the bottleneck is unclear,
measure representative end-to-end latency, startup cost, CPU, or memory at the
expected frequency. Separate plugin work from subprocess and network time.
An isolated interpreter-startup number is not an end-to-end speedup estimate.
Do not require benchmarks for an obviously small command wrapper, and do not
claim a performance benefit solely because a language is compiled.

Record the operating model and runtime requirements in the plugin's README;
keep any language-choice rationale to one short clause. Revisit the choice when
the workload, distribution requirements, or measured constraints change. Port
a working plugin only when the expected benefit justifies the migration and
maintenance cost; preserve its behavioral tests.
