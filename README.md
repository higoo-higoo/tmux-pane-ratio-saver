# tmux-pane-ratio-saver

`tmux-pane-ratio-saver` keeps the split ratios of panes when the outer tmux
window changes size. It supports horizontal, vertical, and arbitrarily nested
classic tiled layouts.

The plugin always scales from the last user-defined reference layout. It does
not feed a rounded result into the next resize, so repeatedly growing and
shrinking a window does not accumulate drift. Manual pane operations such as
`resize-pane`, `split-window`, `kill-pane`, `select-layout`, `swap-pane`, and
`rotate-window` become the new reference instead of being undone.

## Requirements

- tmux 3.3 or later
- a POSIX shell and POSIX awk
- standard `od`, `sed`, `tr`, and `sort` utilities

There are no runtime dependencies on jq, Python, Ruby, or Perl.

## Installation

With [TPM](https://github.com/tmux-plugins/tpm), add the plugin to `.tmux.conf`:

```tmux
set -g @plugin 'higoo-higoo/tmux-pane-ratio-saver'
```

Then press `prefix` + <kbd>I</kbd>, or install it with TPM's command line.

For a manual installation, clone the repository and source its entrypoint:

```tmux
run-shell '/path/to/tmux-pane-ratio-saver/tmux-pane-ratio-saver.tmux'
```

The entrypoint can be run again when reloading tmux configuration. Reloading
replaces only the plugin's indexed hooks and preserves existing references.

## Configuration

The defaults are:

```tmux
set -g @pane-ratio-saver-enabled on
set -g @pane-ratio-saver-debug off
```

Either option may be overridden for one window:

```tmux
set -w @pane-ratio-saver-enabled off
```

Debug mode reports invalid layouts and failed applications. Normal operation
does not display a message for each hook.

## Commands

Capture the current pane arrangement as the new reference:

```sh
/path/to/tmux-pane-ratio-saver/scripts/capture-reference.sh '#{window_id}'
```

For example, bind it to `prefix` + <kbd>R</kbd>:

```tmux
bind-key R run-shell '/path/to/tmux-pane-ratio-saver/scripts/capture-reference.sh #{window_id}'
```

Clear all plugin state for the current window:

```sh
/path/to/tmux-pane-ratio-saver/scripts/clear-state.sh '#{window_id}'
```

The next relevant hook captures a fresh reference after state is cleared.

## Behavior and limitations

State is stored in window-scoped tmux user options. Linked windows therefore
share one reference, and state lasts for the lifetime of the tmux server. Disk
persistence and tmux-resurrect integration are not included.

Resizing while a pane is zoomed is deferred so the plugin does not unzoom it.
The reference layout is restored by the first layout hook after unzooming. If a
window is temporarily too small, the reference is retained and is used again
when space is available.

Only tmux's classic tiled layout syntax is accepted. Floating panes and unknown
future layout formats fail open: the plugin leaves the current layout alone.
Applying a layout may update tmux's internal old-layout history, so exact
preservation of `select-layout -o` history is not supported.

## Development

Run the unit and isolated-server integration suites with Bats:

```sh
bats tests/unit
bats tests/integration
```

Run static checks with:

```sh
shellcheck -x -P scripts tmux-pane-ratio-saver.tmux scripts/*.sh lib/checksum.sh
```

The integration suite starts each test with a dedicated `tmux -L` socket and
includes more than 100 successive resizes to verify that ratios do not drift.
See [implementation.md](implementation.md) for the full format, scaling, and
state-machine design.
