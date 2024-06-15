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

# A recipe to print out help message
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


# A file marker that signifies that the snap has been built
$(build_tag): snap/snapcraft.yaml
	@echo "==Building SNAP=="
	snapcraft
	ls -rt  *.snap | tail -1 > $(build_tag)


# Short-hand recipe for building the snap
build: $(build_tag)


# A file marker that signifies the snap has been installed in
# the system successfully.
$(install_tag): $(build_tag)
	@echo "==Installing SNAP $(package_name)=="
	sudo snap install $(shell cat $(build_tag)) --dangerous
	touch $(install_tag)


# Short-hand recipe to install the snap onto the system
install: $(install_tag)


# Recipe that uninstalls the snap from the system
uninstall:
	@echo "==Uninstall SNAP $(package_name)=="
	sudo snap remove $(package_name)
	rm -f $(install_tag)


# A market that signifies that MicroK8s has been installed and
# configured successfully.
$(k8s_tag):
	/bin/bash ./tests/integration/setup-microk8s.sh
	sg microk8s ./tests/integration/config-microk8s.sh
	touch $(k8s_tag)


# A market that signifies that AWS CLI has been installed and
# configured successfully.
$(aws_tag): $(k8s_tag)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-aws-cli.sh
	touch $(aws_tag)


# A market that signifies that Azure CLI has been installed and
# configured successfully.
$(azure_tag):
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-azure-cli.sh
	touch $(azure_tag)


# Short-hand resipe for installing and configuring K8s cluster
microk8s: $(k8s_tag)


# Short-hand recipe for installing and configuring AWS S3 CLI
aws: $(aws_tag)


# Short-hand recipe for installing and configuring Azure CLI
azure: $(azure_tag)


# Recipe for running integration tests.
integration-tests: $(k8s_tag) $(aws_tag) $(azure_tag)
ifndef SNAP_EXISTS
	@echo "Installing snap first"
	make install
endif
	@export AZURE_STORAGE_ACCOUNT=$(AZURE_STORAGE_ACCOUNT) \
				AZURE_STORAGE_KEY=$(AZURE_STORAGE_KEY) \
	&& sg microk8s tests/integration/ie-tests.sh


# Recipe for cleaning the building environment. 
# Deletes cache files and cleans snapcraft
clean:
	@echo "==Cleaning environment=="
	rm -rf .make_cache .coverage .kube
	rm -rf $(shell find . -name "*.pyc") $(shell find . -name "__pycache__")
	snapcraft clean
