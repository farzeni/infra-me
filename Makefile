ENV        ?= test
REPO_PATH  ?= /opt/infra

TEST_HOST  := root@46.225.170.110
PROD_HOST  := root@TBD

host = $(if $(filter prod,$(ENV)),$(PROD_HOST),$(TEST_HOST))
ssh  = ssh $(host)

.PHONY: deploy status bootstrap

# Deploy all stacks (or pass STACKS="caddy openwebui" to limit)
deploy:
	$(ssh) "cd $(REPO_PATH) && git pull && ./run.sh prod $(or $(STACKS),all)"

# Deploy a single stack: make deploy-caddy ENV=prod
deploy-%:
	$(ssh) "cd $(REPO_PATH) && git pull && ./run.sh prod $*"

status:
	$(ssh) "cd $(REPO_PATH) && ./run.sh status"

# Bootstrap a fresh server. Requires REPO_URL.
# Example: make bootstrap ENV=test REPO_URL=https://github.com/user/infra-me.git
bootstrap:
	@test -n "$(REPO_URL)" || { echo "Usage: make bootstrap ENV=test REPO_URL=<git-clone-url>"; exit 1; }
	ssh root@$(host) "REPO_URL=$(REPO_URL) bash -s" < bootstrap.sh
