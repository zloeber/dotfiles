CFSSL_VERSION ?= 1.5.0
PKI_CERT_PATH ?= $(LOCAL_PATH)/certs
cfssl := $(PROJECT_BIN_PATH)/cfssl
cfssljson := $(PROJECT_BIN_PATH)/cfssljson

OS ?= darwin
ARCH ?= amd64

.PHONY: .dep/cfssl
.dep/cfssl: ## Install local cfssl binary
ifeq (,$(wildcard $(cfssl)))
	@echo "Attempting to install cfssl - $(CFSSL_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_${OS}_${ARCH} \
		-o $(cfssl)
	@chmod +x $(cfssl)
endif
	@echo "cfssl binary: $(cfssl)"

.PHONY: .dep/cfssljson
.dep/cfssljson: ## Install local cfssljson binary
ifeq (,$(wildcard $(cfssl)))
	@echo "Attempting to install cfssljson - $(CFSSL_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_${OS}_${ARCH} \
		-o $(cfssljson)
	@chmod +x $(cfssljson)
endif
	@echo "cfssljson binary: $(cfssljson)"

.PHONY: pki/root
pki/root: .dep/cfssl .dep/cfssljson ## Create a root ca with cfssl
	@mkdir -p $(PKI_CERT_PATH)
	@$(cfssl) genkey -initca $(CONFIG_PATH)/root-ca-template.json | $(cfssljson) -bare $(PKI_CERT_PATH)/root-cert
	@echo "Root certificate location: $(PKI_CERT_PATH)/root-cert"

.PHONY: pki/int/csr
pki/int/csr: ## Generates issuing-ca.csr from KV
	@$(vault) kv get -field=certificate  controller/kv/controller/pki_ca2/csr > $(PKI_CERT_PATH)/issuing-ca.csr
	@echo "CSR nabbed from KV: $(PKI_CERT_PATH)/issuing-ca.csr"

.PHONY: pki/root/sign
pki/root/sign: ## Generates issuing.pem from issuing-ca.csr
	@$(cfssl) sign -ca $(PKI_CERT_PATH)/root-cert.pem \
		-ca-key $(PKI_CERT_PATH)/root-cert-key.pem \
		-hostname dev.localhost -config $(CONFIG_PATH)/root-ca-signing-config.json \
		$(PKI_CERT_PATH)/issuing-ca.csr | jq '.cert' -r | sed '/^$$/d' \
		> $(PKI_CERT_PATH)/issuing.pem
	@echo "Signed CSR: $(PKI_CERT_PATH)/issuing.pem"

.PHONY: pki/vault/config
pki/vault/config: ## Uploaded signed CSR to vault configuration
	$(vault) write pki/ca2/intermediate/set-signed certificate=@$(PKI_CERT_PATH)/issuing.pem
