# Vault Playground V3.0.1 Makefile

# Help Helper matches comments at the start of the task block so make help gives users information about each task
.PHONY: help
help: ## Displays information about available make tasks
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: init
init: ## Spin up local Docker instances for all dependencies on a dedicated Docker network
	@cd tasks && ./init

.PHONY: destroy
destroy: ## Destroy local Docker instances and their Docker network
	@cd tasks && ./destroy

.PHONY: snapshot
snapshot: ## Backup the state of Vault by taking a backup of DynamoDB
	@cd tasks && ./snapshot

.PHONY: snapshots
snapshots: ## Lists all available snapshots in the cache and whether creds are cached for it
	@cd tasks && ./snapshots

.PHONY: purge
purge: ## Delete the local cache of snapshots and initialization keys
	@cd tasks && ./purge

.PHONY: restore
restore: ## Restore previous Vault state by restoring a DynamoDB backup
	@cd tasks && ./restore

.PHONY: creds
creds: ## Shows the root token and unseal keys for the currently running Vault instance if cached
	@cd tasks && ./creds

.PHONY: status
status: ## Displays the current state of the Vault Playground network in Docker.
	@cd tasks && ./status

.PHONY: vault-leader
vault-leader: ## Displays the address of the current Vault leader
	@cd tasks && ./vault-leader