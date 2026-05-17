.PHONY: all proto lint format test build clean

all: proto lint test

proto:
	@echo "Generating gRPC stubs from proto..."
	@mkdir -p services/inference/sangeet_inference/proto
	@mkdir -p packages/audio-engine/Sources/AudioEngine/Generated
	# Generate Python stubs
	python3 -m grpc_tools.protoc \
		--proto_path=proto \
		--python_out=services/inference/sangeet_inference/proto \
		--grpc_python_out=services/inference/sangeet_inference/proto \
		proto/sangeet/v1/*.proto
	# Generate Swift stubs
	protoc \
		--proto_path=proto \
		--swift_out=packages/audio-engine/Sources/AudioEngine/Generated \
		--grpc-swift_out=packages/audio-engine/Sources/AudioEngine/Generated \
		proto/sangeet/v1/*.proto

lint:
	@echo "Running linters..."
	# Python daemon checks
	@if [ -d "services/inference" ]; then \
		cd services/inference && ruff check . && mypy sangeet_inference/; \
	fi
	# Swift frontend & package checks
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint; \
	fi

format:
	@echo "Formatting codebase..."
	@if [ -d "services/inference" ]; then \
		cd services/inference && black . && ruff format .; \
	fi

test:
	@echo "Running test suites..."
	# Python unit tests
	@if [ -d "services/inference" ]; then \
		cd services/inference && pytest; \
	fi
	# Swift unit tests
	@swift test --package-path packages/audio-engine

build:
	@echo "Building daemon binary package..."
	chmod +x scripts/build-daemon.sh
	./scripts/build-daemon.sh

clean:
	@echo "Cleaning up build artifacts..."
	rm -rf services/inference/build services/inference/dist services/inference/.mypy_cache services/inference/.pytest_cache
	rm -rf packages/audio-engine/.build
	rm -rf build/DerivedData dist/

release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION parameter is required. Usage: make release VERSION=0.10.0-beta1 [SIGNING_IDENTITY=...]"; \
		exit 1; \
	fi
	@SIGNING_IDENT="$${SIGNING_IDENTITY:--}"; \
	echo "Orchestrating release for Sangeet AI version $(VERSION) with identity '$${SIGNING_IDENT}'..."; \
	./scripts/release.sh "$${SIGNING_IDENT}" "$(VERSION)"
