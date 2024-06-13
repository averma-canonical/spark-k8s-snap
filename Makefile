# Makefile macros (or variables) are defined a little bit differently than traditional bash, keep in mind that in the Makefile there's top-level Makefile-only syntax, and everything else is bash script syntax.

# .PHONY defines parts of the makefile that are not dependant on any specific file
# This is most often used to store functions
.PHONY = help setup build install uninstall integration-test clean

# Uncomment to store cache installation in the environment
# package_dir := $(shell python -c 'import site; print(site.getsitepackages()[0])')
package_dir := .make_cache
package_name=$(shell grep 'name:' snap/snapcraft.yaml | tail -n1 | awk '{print $$2}')


$(shell mkdir -p $(package_dir))

SNAP_EXISTS := $(shell snap list | grep $(package_name) 2> /dev/null)

pre_deps_tag := $(package_dir)/.pre_deps
build_tag := $(package_dir)/.build_tag
install_tag := $(package_dir)/.install_tag
k8s_tag := $(package_dir)/.k8s_tag
aws_tag := $(package_dir)/.aws_tag
azure_tag := $(package_dir)/.azure_tag


# ======================
# Rules and Dependencies
# ======================

help:
	@echo "---------------HELP-----------------"
	@echo "Package Name: $(package_name)"
	@echo " "
	@echo "Type 'make' followed by one of these keywords:"
	@echo " "
	@echo "  - setup for installing base requirements"
	@echo "  - build for creating the SNAP file"
	@echo "  - install for installing the package"
	@echo "  - uninstall for uninstalling the environment"
	@echo "  - integration-test for running integration tests"
	@echo "  - clean for removing cache file"
	@echo "------------------------------------"

$(build_tag): snap/snapcraft.yaml
	@echo "==Building SNAP=="
	snapcraft
	ls -rt  *.snap | tail -1 > $(build_tag)

build: $(build_tag)

$(install_tag): $(build_tag)
	@echo "==Installing SNAP $(package_name)=="
	sudo snap install $(shell cat $(build_tag)) --dangerous
	touch $(install_tag)

install: $(install_tag)

uninstall:
	@echo "==Uninstall SNAP $(package_name)=="
	sudo snap remove $(package_name)
	rm -f $(install_tag)

$(k8s_tag):
	/bin/bash ./tests/integration/setup-microk8s.sh
	sg microk8s ./tests/integration/config-microk8s.sh
	touch $(k8s_tag)

$(aws_tag): $(k8s_tag)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-aws-cli.sh
	touch $(aws_tag)

$(azure_tag): $(k8s_tag)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-azure-cli.sh
	touch $(azure_tag)

microk8s: $(k8s_tag)

install_if_missing: microk8s

integration-tests: $(k8s_tag) $(aws_tag) $(azure_tag)
ifndef SNAP_EXISTS
	@echo "Installing snap first"
	make install
	sg microk8s tests/integration/ie-tests.sh
else
	@echo "snap already installed"
	sg microk8s tests/integration/ie-tests.sh
endif

clean:
	@echo "==Cleaning environment=="
	rm -rf .make_cache .coverage .kube
	rm -rf $(shell find . -name "*.pyc") $(shell find . -name "__pycache__")
	snapcraft clean
