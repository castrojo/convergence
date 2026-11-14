// Package testhome points os.UserHomeDir at a scratch directory for the
// duration of a test on every platform.
package testhome

import "testing"

// Set makes dir the home directory for the rest of the test. It sets both
// HOME (Unix) and USERPROFILE (Windows) so tests never write into the real
// profile of whoever runs the suite.
func Set(t testing.TB, dir string) {
	t.Helper()
	t.Setenv("HOME", dir)
	t.Setenv("USERPROFILE", dir)
}

// New creates a fresh temporary directory, makes it the home directory and
// returns it.
func New(t testing.TB) string {
	t.Helper()
	dir := t.TempDir()
	Set(t, dir)
	return dir
}
