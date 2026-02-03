.PHONY: test test-file test-integration deps clean

# Run all unit tests
test: deps
	nvim --headless --clean -u tests/minimal_init.lua -c "lua MiniTest.run()"

# Run a specific test file: make test-file FILE=tests/test_schema.lua
test-file: deps
	nvim --headless --clean -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Run integration tests (starts server, tests with curl)
test-integration:
	./tests/integration_test.sh

# Run all tests
test-all: test test-integration

# Ensure dependencies are installed
deps:
	@if [ ! -d deps/mini.nvim ]; then \
		mkdir -p deps && \
		git clone --depth=1 https://github.com/echasnovski/mini.nvim deps/mini.nvim; \
	fi

# Clean up
clean:
	rm -rf deps
