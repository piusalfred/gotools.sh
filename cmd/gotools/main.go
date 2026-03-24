// Copyright (c) 2026 Pius Alfred
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"github.com/piusalfred/gotools"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	if err := Run(ctx, os.Args); err != nil {
		// If the context was cancelled due to a signal, exit with the
		// conventional 128+signal code so callers (scripts, CI, etc.)
		// can distinguish a signal-killed process from a regular failure.
		if ctx.Err() != nil {
			// Determine which signal fired. Default to SIGINT if we
			// cannot tell — this matches the common Ctrl-C case.
			code := 128 + int(syscall.SIGINT)

			var exitErr *exec.ExitError
			if errors.As(err, &exitErr) {
				code = exitErr.ExitCode()
			}

			os.Exit(code)
		}

		// Propagate the child's exit code when available.
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			os.Exit(exitErr.ExitCode())
		}

		fmt.Fprintf(os.Stderr, "gotools: %v\n", err)
		os.Exit(1)
	}
}

// Run executes the embedded gotools.sh script with the supplied arguments.
// The context controls the lifetime of the child process: cancelling it
// sends SIGKILL to the process group (the default CommandContext behaviour).
func Run(ctx context.Context, args []string) error {
	script := []string{"-c", gotools.SCRIPT, "gotools"}
	if len(args) > 1 {
		script = append(script, args[1:]...)
	}

	cmd := exec.CommandContext(ctx, "bash", script...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	// Put the child in its own process group so that signals sent to the
	// gotools binary are not automatically forwarded by the kernel. We
	// handle cancellation through the context instead, which gives us a
	// chance to exit cleanly.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	// When the context is cancelled, send SIGTERM first so the shell
	// script (and any children it spawned) can clean up before we
	// escalate to SIGKILL after the grace period.
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}

		// Signal the entire process group (negative PID).
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	}

	// Give the child process a grace period to handle SIGTERM and shut
	// down cleanly. If it is still running after WaitDelay, Go will
	// send SIGKILL to force-terminate it.
	cmd.WaitDelay = 5 * time.Second

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("execution failed: %w", err)
	}

	return nil
}
