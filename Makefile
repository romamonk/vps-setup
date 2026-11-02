ANSIBLE := .venv/bin/ansible-playbook

.PHONY: lint syntax
lint:
	.venv/bin/yamllint .
	ANSIBLE_HOME="$(CURDIR)/.ansible" PATH="$(CURDIR)/.venv/bin:$$PATH" .venv/bin/ansible-lint --offline

syntax:
	$(ANSIBLE) -i inventories/example/hosts.yml playbooks/bootstrap.yml --syntax-check
	$(ANSIBLE) -i inventories/example/hosts.yml playbooks/configure.yml --syntax-check
	$(ANSIBLE) -i inventories/example/hosts.yml playbooks/harden.yml --syntax-check
	$(ANSIBLE) -i inventories/example/hosts.yml playbooks/verify.yml --syntax-check
	$(ANSIBLE) -i inventories/example/hosts.yml playbooks/reboot.yml --syntax-check
