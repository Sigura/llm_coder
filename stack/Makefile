# Thin wrappers around scripts/. DRY=1 adds --dry-run to any target.
SHELL := bash
S := scripts
FLAGS := $(if $(DRY),--dry-run)
need_m = $(if $(M),,$(error M=<model-id> is required, e.g. make $@ M=deepseek-v4.1-flash-1017))

.PHONY: help check bootstrap build download bench install health client rollback serve lint

help:
	@echo "make check [M=id]               pre-flight checks (00)"
	@echo "sudo make bootstrap [SRC=repo] [DROP_CACHES=1]  one-time host setup (05)"
	@echo "make build [REF=tag]            build + smoke-test llama.cpp, switch -current (10)"
	@echo "make download M=id              download + verify pinned weights (20)"
	@echo "make bench M=id [PHASES=fit,numa,spec]  tune + benchmark, update model .env (30)"
	@echo "sudo make install M=id          install/restart llm@id and health-check it (40)"
	@echo "make health M=id                health check of the running service (50)"
	@echo "make client M=id                merge OpenCode provider config (60)"
	@echo "sudo make rollback M=id | E=1   roll back a model or the engine (90)"
	@echo "make serve M=id                 run the server in the foreground (what systemd runs)"
	@echo "make lint                       shellcheck all scripts"

check:
	$(S)/00-check-host.sh $(FLAGS) $(M)

bootstrap:
	$(S)/05-bootstrap-host.sh $(FLAGS) $(if $(SRC),--source $(SRC)) $(if $(DROP_CACHES),--allow-drop-caches)

build:
	$(S)/10-build-engine.sh $(FLAGS) $(if $(REF),--ref $(REF))

download:
	$(need_m)
	$(S)/20-download-model.sh $(FLAGS) $(M)

bench:
	$(need_m)
	$(S)/30-benchmark.sh $(FLAGS) $(if $(PHASES),--phases $(PHASES)) $(M)

install:
	$(need_m)
	$(S)/40-install-service.sh $(FLAGS) $(M)

health:
	$(need_m)
	$(S)/50-healthcheck.sh $(FLAGS) $(M)

client:
	$(need_m)
	$(S)/60-client-config.sh $(FLAGS) $(M)

rollback:
	$(if $(E),,$(need_m))
	$(S)/90-rollback.sh $(FLAGS) $(if $(E),engine,$(M))

serve:
	$(need_m)
	$(S)/llm-serve.sh $(FLAGS) $(M)

lint:
	shellcheck -x -P $(S) $(S)/*.sh
