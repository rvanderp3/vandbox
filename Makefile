IMAGE_NAME ?= vandbox
IMAGE_TAG ?= latest
RECORD_TAG ?= record
OPENCODE_TAG ?= opencode

.PHONY: build build-record build-opencode run record run-opencode mcp-up mcp-down mcp-logs shell lint test-network test-binary clean

build:
	podman build -t $(IMAGE_NAME):$(IMAGE_TAG) .

build-record:
	podman build --build-arg INSTALL_STRACE=1 -t $(IMAGE_NAME):$(RECORD_TAG) .

build-opencode:
	podman build -f Containerfile.opencode \
		--build-arg HOST_UID=$$(id -u) \
		--build-arg HOST_GID=$$(id -g) \
		-t $(IMAGE_NAME):$(OPENCODE_TAG) .

run: build
	./run.sh

run-opencode: build-opencode
	./run-opencode.sh

record: build-record
	./record.sh

mcp-up:
	podman-compose -f docker-compose.mcp.yml up -d --build

mcp-down:
	podman-compose -f docker-compose.mcp.yml down

mcp-logs:
	podman-compose -f docker-compose.mcp.yml logs -f

shell: build
	podman run --rm -it \
		--name vandbox-debug \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		/bin/bash

lint:
	@echo "Checking seccomp profiles..."
	@python3 -m json.tool seccomp/default.json > /dev/null && echo "  default.json: OK"
	@python3 -m json.tool seccomp/record.json > /dev/null && echo "  record.json: OK"
	@if [ -f seccomp/generated.json ]; then \
		python3 -m json.tool seccomp/generated.json > /dev/null && echo "  generated.json: OK"; \
	fi
	@echo "Checking binary allowlist paths..."
	@echo "  (paths are validated inside the container at runtime)"
	@echo "Lint passed."

test-network: build
	@echo "Testing network restrictions..."
	@echo "--- Denied traffic (should fail) ---"
	-podman run --rm \
		--security-opt seccomp=seccomp/default.json \
		--cap-add=NET_ADMIN \
		--read-only --read-only-tmpfs \
		-v $$(pwd)/config/network-allowlist.conf:/opt/vandbox/config/network-allowlist.conf:ro,Z \
		-v $$(pwd)/config/binary-allowlist.conf:/opt/vandbox/config/binary-allowlist.conf:ro,Z \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash -c "python3 -c \"import urllib.request; urllib.request.urlopen('http://example.com', timeout=5)\" 2>&1 || echo 'PASS: Connection blocked'"
	@echo ""
	@echo "Network test complete."

test-binary: build
	@echo "Testing binary restrictions..."
	@podman run --rm \
		--security-opt seccomp=seccomp/default.json \
		--cap-add=NET_ADMIN \
		--read-only --read-only-tmpfs \
		-v $$(pwd)/config/network-allowlist.conf:/opt/vandbox/config/network-allowlist.conf:ro,Z \
		-v $$(pwd)/config/binary-allowlist.conf:/opt/vandbox/config/binary-allowlist.conf:ro,Z \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash -c "echo 'Allowed:'; ls /tmp > /dev/null && echo '  ls: OK'; python3 -c 'print(\"hello\")' && echo '  python3: OK'; echo 'Blocked:'; curl --version 2>&1 || echo '  curl: BLOCKED (OK)'"
	@echo ""
	@echo "Binary test complete."

clean:
	-podman rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null
	-podman rmi $(IMAGE_NAME):$(RECORD_TAG) 2>/dev/null
	-podman rmi $(IMAGE_NAME):$(OPENCODE_TAG) 2>/dev/null
	rm -rf workspace audit-logs
	rm -f seccomp/generated.json
