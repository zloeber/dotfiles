OPENLDAP_VERSION ?= 1.7.1
openldap := $(PROJECT_BIN_PATH)/openldap

# Setup proper openldap provider variables
OPENLDAP_IMAGE=osixia/openldap:latest
OPENLDAP_ADDRESS:=$(shell $(docker_cmd) inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' openldap 2> /dev/null)
OPENLDAP_ADMIN_PASS:=2LearnVault
OPENLDAP_USER_PASS:=1LearnedVault
OPENLDAP_DOMAIN:=contoso.domain
OPENLDAP_DOMAIN_DN:=dc=contoso,dc=domain
OPENLDAP_ORG:=contoso
OPENLDAP_URL:=ldap://$(OPENLDAP_ADDRESS)

define OPENLDAP_INIT
dn: ou=groups,$(OPENLDAP_DOMAIN_DN)
objectClass: organizationalunit
objectClass: top
ou: groups
description: groups of users

dn: ou=Service Accounts,$(OPENLDAP_DOMAIN_DN)
objectClass: organizationalunit
objectClass: top
ou: Service Accounts
description: Service Accounts

dn: cn=app1-svc,ou=Service Accounts,$(OPENLDAP_DOMAIN_DN)
objectClass: person
objectClass: top
cn: app1-svc
sn: svc
userPassword: $(OPENLDAP_USER_PASS)

dn: ou=users,$(OPENLDAP_DOMAIN_DN)
objectClass: organizationalunit
objectClass: top
ou: users
description: users

dn: cn=alice,ou=users,$(OPENLDAP_DOMAIN_DN)
objectClass: person
objectClass: top
cn: alice
sn: worker
memberOf: cn=dev,ou=groups,$(OPENLDAP_DOMAIN_DN)
userPassword: $(OPENLDAP_USER_PASS)

dn: cn=dev,ou=groups,$(OPENLDAP_DOMAIN_DN)
objectClass: groupofnames
objectClass: top
description: Developers group
cn: dev
member: cn=alice,ou=users,$(OPENLDAP_DOMAIN_DN)

dn: cn=vault-admin,ou=users,$(OPENLDAP_DOMAIN_DN)
objectClass: person
objectClass: top
cn: vault
sn: admin
userPassword: $(OPENLDAP_ADMIN_PASS)

dn: cn=Administrators,ou=groups,$(OPENLDAP_DOMAIN_DN)
objectClass: groupOfNames
objectClass: top
cn: Administrators
member: cn=vault-admin,ou=users,$(OPENLDAP_DOMAIN_DN)
member: cn=admin,$(OPENLDAP_DOMAIN_DN)
description: Administrators

olcAccess: to attrs=userPassword,shadowLastChange
  by self write
  by anonymous auth
  by dn.base="cn=Administrators,ou=groups,$(OPENLDAP_DOMAIN_DN)" write
  by * none
olcAccess: to *
  by self write
  by dn.base="cn=Administrators,ou=groups,$(OPENLDAP_DOMAIN_DN)" write
  by * read
endef
export OPENLDAP_INIT

.PHONY: openldap/start
openldap/start: ## Start a local openldap dev server in docker
	$(docker_cmd) run \
		--name openldap \
		--env LDAP_ORGANISATION="$(OPENLDAP_ORG)" \
		--env LDAP_DOMAIN="$(OPENLDAP_DOMAIN)" \
		--env LDAP_ADMIN_PASSWORD="$(OPENLDAP_ADMIN_PASS)" \
		-p 389:389 \
		-p 636:636 $(DOCKER_NETWORK) \
		--detach \
		--rm \
		$(OPENLDAP_IMAGE)

.PHONY: openldap/stop
openldap/stop: ## Stop a local openldap dev server in docker
	@echo "Stopping container: openldap"
	@$(docker_cmd) stop openldap 2>/dev/null || true

.PHONY: openldap/ldif
openldap/ldif: ## Generate OpenLDAP initial configuration (ldif)
	@echo "$$OPENLDAP_INIT" > $(CONFIG_PATH)/openldap-init.ldif
	@echo "Created LDIF file: $(CONFIG_PATH)/openldap-init.ldif"

.PHONY: openldap/init
openldap/init: openldap/ldif ## Initialize LDAP
	@ldapadd -cxv \
		-D "cn=admin,$(OPENLDAP_DOMAIN_DN)" \
		-f $(CONFIG_PATH)/openldap-init.ldif \
		-h 127.0.0.1 \
		-w "$(OPENLDAP_ADMIN_PASS)"
	@$(MAKE) openldap/addr/export

.PHONY: openldap/addr
openldap/addr: ## Show the openldap container address
	@printf $(OPENLDAP_ADDRESS)

.PHONY: openldap/addr/export
openldap/addr/export: ## export the openldap container url
	@printf "ldap://$(OPENLDAP_ADDRESS)" > $(CONFIG_PATH)/ldap_url.txt


.PHONY: openldap/show
openldap/show: ## Show openldap information
	@echo "OPENLDAP_ADDRESS: $(OPENLDAP_ADDRESS)"
	@echo "OPENLDAP_URL: $(OPENLDAP_URL)"
	@echo "OPENLDAP_DOMAIN: $(OPENLDAP_DOMAIN)"
	@echo "OPENLDAP_DOMAIN_DN: $(OPENLDAP_DOMAIN_DN)"
	@echo "OPENLDAP_ORG: $(OPENLDAP_ORG)"
	@echo "OPENLDAP_ADMIN_PASS: $(OPENLDAP_ADMIN_PASS)"
	@echo "OPENLDAP_USER_PASS: $(OPENLDAP_USER_PASS)"
	@echo "OPENLDAP_IMAGE: $(OPENLDAP_IMAGE)"

.PHONY: openldap/ui/stop
openldap/ui/stop: ## Stop a local openldap gui
	@echo "Stopping container: openldap-gui"
	@$(docker_cmd) stop openldap-gui 2>/dev/null || true

.PHONY: openldap/ui/start
openldap/ui/start: ## Show openldap GUI interface
	$(docker_cmd) run \
		--detach \
		--rm \
		--name=openldap-gui \
		-p 80:80 $(DOCKER_NETWORK) \
		-e "SERVER_HOSTNAME=localhost" \
		-e "LDAP_URI=$(OPENLDAP_URL)" \
		-e "LDAP_BASE_DN=$(OPENLDAP_DOMAIN_DN)" \
		-e "LDAP_REQUIRE_STARTTLS=TRUE" \
		-e "LDAP_ADMINS_GROUP=admins" \
		-e "LDAP_ADMIN_BIND_DN=cn=admin,$(OPENLDAP_DOMAIN_DN)" \
		-e "LDAP_ADMIN_BIND_PWD=$(OPENLDAP_ADMIN_PASS)"\
		-e "LDAP_IGNORE_CERT_ERRORS=true" \
		-e "EMAIL_DOMAIN=contoso.org" \
		-e "NO_HTTPS=TRUE" \
		wheelybird/ldap-user-manager:latest

.PHONY: openldap/ui
openldap/ui: openldap/ui/stop openldap/ui/start ## Restart and open the openldap gui
	@$(shell open http://localhost/setup)

.PHONY: openldap/test
openldap/test: ## Test search OpenLDAP
	@ldapsearch -x -LLL -h localhost -D "cn=admin,$(OPENLDAP_DOMAIN_DN)" -w $(OPENLDAP_ADMIN_PASS) -b "$(OPENLDAP_DOMAIN_DN)" | awk -v OFS=',' '{split($$0,a,": ")} /^dn:/{dn=a[2]} /^objectClass:/{objectClass=a[2]} /^cn/{cn=a[2]; print dn, objectClass, cn}'
