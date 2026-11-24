.PHONY: check format publish

check:
	cargo fmt --check
	cargo check --all-targets
	cargo test -q

format:
	cargo fmt

publish: check
	cargo publish --workspace
