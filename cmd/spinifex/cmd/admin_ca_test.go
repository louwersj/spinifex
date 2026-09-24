package cmd

import "testing"

func TestCATrustStoreForOSRelease(t *testing.T) {
	tests := []struct {
		name      string
		osRelease string
		path      string
		command   string
		args      []string
		wantErr   bool
	}{
		{
			name:      "Debian 13",
			osRelease: "ID=debian\nVERSION_ID=13\n",
			path:      "/usr/local/share/ca-certificates/spinifex-ca.crt",
			command:   "update-ca-certificates",
		},
		{
			name:      "Ubuntu 24.04",
			osRelease: "ID=ubuntu\nVERSION_ID=24.04\n",
			path:      "/usr/local/share/ca-certificates/spinifex-ca.crt",
			command:   "update-ca-certificates",
		},
		{
			name:      "Oracle Linux 9",
			osRelease: "ID=ol\nVERSION_ID=9.6\n",
			path:      "/etc/pki/ca-trust/source/anchors/spinifex-ca.crt",
			command:   "update-ca-trust",
			args:      []string{"extract"},
		},
		{name: "unsupported Oracle Linux", osRelease: "ID=ol\nVERSION_ID=8.10\n", wantErr: true},
		{name: "unsupported OS", osRelease: "ID=fedora\nVERSION_ID=42\n", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := caTrustStoreForOSRelease([]byte(tt.osRelease))
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got.certificatePath != tt.path || got.updateCommand != tt.command {
				t.Fatalf("got %#v, want path=%q command=%q", got, tt.path, tt.command)
			}
			if len(got.updateArgs) != len(tt.args) {
				t.Fatalf("got args %q, want %q", got.updateArgs, tt.args)
			}
			for i := range tt.args {
				if got.updateArgs[i] != tt.args[i] {
					t.Fatalf("got args %q, want %q", got.updateArgs, tt.args)
				}
			}
		})
	}
}
