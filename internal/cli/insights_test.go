package cli

import (
	"strings"
	"testing"

	"github.com/jeefy/convergence/internal/testhome"
)

func TestParseSince(t *testing.T) {
	cases := []struct {
		input   string
		wantErr bool
	}{
		{"1d", false},
		{"7d", false},
		{"30d", false},
		{"24h", false},
		{"bad", true},
		{"-1d", true},
	}

	for _, c := range cases {
		_, err := parseSince(c.input)
		if (err != nil) != c.wantErr {
			t.Errorf("parseSince(%q) error = %v, wantErr %v", c.input, err, c.wantErr)
		}
	}
}

func TestInsightsCmdNoDB(t *testing.T) {
	testhome.New(t)
	err := runCLI(t, "insights", "--since", "1d")
	if err == nil {
		t.Fatal("expected error when no DB is configured")
	}
	if !strings.Contains(err.Error(), "requires agentgateway's Postgres request log") {
		t.Fatalf("unexpected error message: %v", err)
	}
}
