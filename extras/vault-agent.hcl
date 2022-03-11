exit_after_auth = false
pid_file = "./pidfile"

auto_auth {
    method "jwt" {
        mount_path = "auth/jwt/login""
        config = {
            type = "iam"
            role = "dev-role-iam"
        }
    }

    sink "file" {
        wrap_ttl = "5m"
        config = {
            path = "/home/ubuntu/vault-token-via-agent"
        }
    }
}

vault {
    // This is needed until https://github.com/hashicorp/vault/issues/7889
    // gets fixed, otherwise it is automated by the webhook.
    ca_cert = "/vault/tls/ca.crt"
}
auto_auth {
    method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
        role = "my-role"
    }
    }
    sink "file" {
    config = {
        path = "/vault/.vault-token"
    }
    }
}
template {
    contents = <<EOH
    {{- with secret "database/creds/readonly" }}
    username: {{ .Data.username }}
    password: {{ .Data.password }}
    {{ end }}
    EOH
    destination = "/etc/secrets/config"
    command     = "/bin/sh -c \"kill -HUP $(pidof vault-demo-app) || true\""
}