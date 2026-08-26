.PHONY: help test test-docker

IMAGE ?= ghcr.io/dhis2-chap/docker_r_inla:master

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  test         Run the test suite against the local R installation."
	@echo "               Tests needing the INLA solver skip if it is missing."
	@echo "  test-docker  Run the full suite inside $(IMAGE), which has INLA."

test:
	@Rscript tests/run_tests.R

test-docker:
	@docker run --rm -v "$(CURDIR):/work" -w /work $(IMAGE) sh -c \
		"R -q -e \"if (!requireNamespace('testthat', quietly = TRUE)) install.packages('testthat', repos = 'https://cloud.r-project.org')\" \
		 && Rscript tests/run_tests.R"
