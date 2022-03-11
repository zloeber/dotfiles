dynamodb := $(PROJECT_BIN_PATH)/dynamodb

# Setup proper dynamodb provider variables
DYNAMODB_IMAGE=amazon/dynamodb-local:latest
DYNAMODB_ADDRESS:=$(shell docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dynamodb 2> /dev/null)

.PHONY: dynamodb/start
dynamodb/start:
export DOCKER_NETWORK=--net kind
dynamodb/start: ## Start a local dynamodb dev server in docker
	@docker run \
		--name dynamodb \
		-p 8000:8000 $(DOCKER_NETWORK) \
		--detach \
		--rm \
		$(DYNAMODB_IMAGE) \
		-jar DynamoDBLocal.jar \
		-sharedDb -dbPath .

.PHONY: dynamodb/stop
dynamodb/stop: ## Stop a local dynamodb dev server in docker
	@echo "Stopping container: dynamodb"
	@docker stop dynamodb 2>/dev/null || true

.PHONY: dynamodb/addr
dynamodb/addr: ## Show the dynamodb container address
	@printf $(DYNAMODB_ADDRESS)

.PHONY: dynamodb/show
dynamodb/show: ## List all dynamodb tables via aws cli
	@echo "DynamodB Tables"
	@aws dynamodb list-tables \
		--no-cli-pager \
		--endpoint-url http://localhost:8000

.PHONY: dynamodb/init
dynamodb/init: ## Initialize metrics table
	aws dynamodb create-table \
		--cli-input-json file://$(CONFIG_PATH)/dynamodb_table.json \
		--no-cli-pager \
		--endpoint-url http://localhost:8000

.PHONY: dynamodb/import
dynamodb/import: ## Load data into metrics table
	aws dynamodb put-item --table-name vault-poc-metrics \
		--item file://$(CONFIG_PATH)/dynamodb_table_static.json \
		--no-cli-pager \
		--endpoint-url http://localhost:8000
	aws dynamodb put-item --table-name vault-poc-metrics \
		--item file://$(CONFIG_PATH)/dynamodb_table_dynamic.json \
		--no-cli-pager \
		--endpoint-url http://localhost:8000

.PHONY: dynamodb/query
dynamodb/query: ## Get metric table items
	@aws dynamodb query \
		--table-name vault-poc-metrics \
		--key-condition-expression "Kind = :kind AND #date BETWEEN :startdate AND :enddate" \
		--expression-attribute-names '{"#date":"Date"}' \
		--expression-attribute-values '{ \
			":kind": { "S": "static" }, \
			":startdate": { "S": "20170101" }, \
			":enddate": { "S": "20250101" } \
		}' \
		--no-cli-pager \
		--endpoint-url http://localhost:8000 | jq
	@aws dynamodb query \
		--table-name vault-poc-metrics \
		--key-condition-expression "Kind = :kind AND #date BETWEEN :startdate AND :enddate" \
		--expression-attribute-names '{"#date":"Date"}' \
		--expression-attribute-values '{ \
			":kind": { "S": "dynamic" }, \
			":startdate": { "S": "20170101" }, \
			":enddate": { "S": "20250101" } \
		}' \
		--no-cli-pager \
		--endpoint-url http://localhost:8000 | jq